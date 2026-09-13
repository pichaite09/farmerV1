"""Run ON THE HOST only after tests/review and protected backups pass.

prepare builds without downtime. activate quiesces ALL old writers before the
migration and starts only the API. worker is a separate, explicit final gate.
Never reset historical outbox rows. Do not use --remove-orphans.
"""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import time
import urllib.request
import yaml

ROOT = Path('/opt/stacks/farmer-main')
COMPOSE = ROOT / 'compose.yaml'
API = 'farmer-main-api-1'
WORKER = 'farmer-main-scheduler-1'


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def inspect(name):
    return json.loads(subprocess.check_output(['docker', 'inspect', name]))[0]


def compose(*args):
    return run('docker', 'compose', '-f', str(COMPOSE), *args)


def prepare(image):
    model = yaml.safe_load(COMPOSE.read_text())
    api = model['services']['api']
    assert api['build'] == './backend'
    assert api['volumes'] == ['attachment_data:/data/attachments']
    assert all(k in api['environment'] for k in ('DATABASE_URL', 'JWT_SECRET', 'FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY'))
    assert all(n in api['networks'] for n in ('private', 'edge'))
    api['image'] = image
    worker = {key: copy.deepcopy(api[key]) for key in (
        'image', 'build', 'restart', 'environment', 'volumes', 'networks', 'security_opt', 'cap_drop')}
    worker.update(profiles=['notifications'], command=['python', '-m', 'app.scheduler'],
                  depends_on={'api': {'condition': 'service_healthy'}, 'postgres': {'condition': 'service_healthy'}},
                  healthcheck={'disable': True})
    model['services']['scheduler'] = worker
    temp = COMPOSE.with_suffix('.candidate.yaml')
    temp.write_text(yaml.safe_dump(model, sort_keys=False))
    temp.chmod(0o600)
    run('docker', 'compose', '-f', str(temp), '--profile', 'notifications', 'config', '--quiet')
    temp.replace(COMPOSE)
    compose('build', 'api')
    print('prepared image=' + image, flush=True)


def quiesce_old_writers():
    # Stop is blocking: Docker waits for graceful completion, then kills remaining
    # processes. Read back both states before touching the activation boundary.
    run('docker', 'stop', '--time', '30', WORKER, API)
    for name in (WORKER, API):
        assert not inspect(name)['State']['Running'], 'old writer still running'
    # Verify no extra API/worker replica from this Compose project exists.
    ids = subprocess.check_output(['docker', 'ps', '-q', '--filter', 'label=com.docker.compose.project=farmer-main'], text=True).split()
    for cid in ids:
        labels = inspect(cid)['Config']['Labels']
        assert labels.get('com.docker.compose.service') not in ('api', 'scheduler')
    print('old API and scheduler quiesced before migration', flush=True)


def activate():
    quiesce_old_writers()
    # Persist the pre-activation snapshot only after old HTTP writers are stopped.
    snapshot = Path('/opt/backups/farmer-main-notifications/activation-before.json')
    with snapshot.open('w') as out:
        run('python3', str(ROOT / 'announcement_history_snapshot.py'), stdout=out)
    snapshot.chmod(0o600)
    compose('run', '--rm', '--no-deps', 'api', 'alembic', 'upgrade', 'head')
    compose('up', '-d', '--no-deps', '--force-recreate', 'api')
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen('http://127.0.0.1:8090/health/ready', timeout=5) as response:
                assert response.status == 200
            assert inspect(API)['State']['Health']['Status'] == 'healthy'
            print('API ready; worker remains stopped', flush=True)
            return
        except Exception:
            time.sleep(2)
    raise RuntimeError('API readiness failed; worker remains stopped')


def verify_runtime_parity(api, worker):
    assert api['Image'] == worker['Image'], 'image mismatch'
    assert sorted(api['Config']['Env']) == sorted(worker['Config']['Env']), 'environment mismatch'
    env = dict(item.split('=', 1) for item in worker['Config']['Env'])
    assert all(env.get(key) for key in ('FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY')), 'missing Firebase configuration'
    def mounts(container):
        return sorted((m['Type'], m.get('Name', m.get('Source')), m['Destination'], m['RW']) for m in container['Mounts'])
    assert mounts(api) == mounts(worker), 'mount mismatch'
    assert set(api['NetworkSettings']['Networks']) == set(worker['NetworkSettings']['Networks']), 'network mismatch'


def worker():
    api = inspect(API)
    assert api['State']['Health']['Status'] == 'healthy'
    compose('--profile', 'notifications', 'up', '--no-start', '--no-deps', '--force-recreate', 'scheduler')
    candidate = inspect(WORKER)
    verify_runtime_parity(api, candidate)
    compose('--profile', 'notifications', 'start', 'scheduler')
    live = inspect(WORKER)
    verify_runtime_parity(api, live)
    assert live['State']['Running']
    print('API/scheduler image, environment, mounts and networks match', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=['prepare', 'activate', 'worker'])
    parser.add_argument('--image')
    args = parser.parse_args()
    if args.phase == 'prepare':
        assert args.image and args.image.startswith('farmer-main-api:')
        prepare(args.image)
    elif args.phase == 'activate':
        activate()
    else:
        worker()
