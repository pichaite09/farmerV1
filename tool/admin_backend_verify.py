"""Run on staging host only; disposable synthetic DB, no production access."""
import json
import secrets
import subprocess
import sys
from pathlib import Path


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


network = 'farmer-admin-ux-test'
pg = 'farmer-admin-ux-test-postgres'
image = json.loads(subprocess.check_output(['docker', 'inspect', 'farmer-main-staging-api-1']))[0]['Config']['Image']
if sys.argv[1] == 'setup':
    password = secrets.token_hex(24)
    env = Path('/tmp/farmer-admin-ux-test.env')
    env.write_text(f'DATABASE_URL=postgresql+psycopg://postgres:{password}@postgres:5432/farmer_main_test\nJWT_SECRET={secrets.token_hex(48)}\nCORS_ORIGINS=["http://localhost"]\nALLOW_DESTRUCTIVE_TEST_DB=1\n')
    env.chmod(0o600)
    run('docker', 'network', 'create', network)
    run('docker', 'run', '-d', '--name', pg, '--network', network, '--network-alias', 'postgres', '-e', f'POSTGRES_PASSWORD={password}', '-e', 'POSTGRES_DB=farmer_main_test', 'postgres:16-alpine')
else:
    run('docker', 'run', '--rm', '--network', network, '--env-file', '/tmp/farmer-admin-ux-test.env', '-v', '/tmp/farmer-admin-ux-backend:/app', '-w', '/app', image, 'sh', '-c', 'alembic upgrade head && python -m pytest ' + ('tests/test_admin.py -k all_records -q' if sys.argv[1] == 'red' else 'tests -q'))
