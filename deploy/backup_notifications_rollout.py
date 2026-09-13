"""Protected, read-verified backups before notification maintenance (remote host)."""
from pathlib import Path
from datetime import datetime, timezone
import os
import subprocess
import hashlib
import json
os.umask(0o077)
root = Path('/opt/backups/farmer-main-notifications') / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
root.mkdir(parents=True, mode=0o700)
def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)
with (root/'database.dump').open('wb') as out:
    run(['docker','exec','farmer-main-postgres-1','pg_dump','-U','farmer_main','-d','farmer_main','-Fc'], stdout=out)
with (root/'database.dump').open('rb') as inp, (root/'database.list').open('wb') as out:
    run(['docker','exec','-i','farmer-main-postgres-1','pg_restore','--list'], stdin=inp, stdout=out)
assert (root/'database.list').stat().st_size > 1000
for name, base, paths in [
    ('backend-config.tgz','/opt/stacks/farmer-main',['backend','compose.yaml','.env']),
    ('web-config.tgz','/opt/stacks/farmer-main-production',['web','compose.yaml','nginx.conf']),
    ('attachments.tgz','/var/lib/docker/volumes/farmer_main_attachment_data',['_data'])]:
    run(['tar','czf',str(root/name),'-C',base,*paths])
    run(['tar','tzf',str(root/name)], stdout=subprocess.DEVNULL)
with (root/'containers.json').open('wb') as out:
    run(['docker','inspect','farmer-main-api-1','farmer-main-scheduler-1','farmer-main-production-web-1','farmer-main-postgres-1'],stdout=out)
manifest = {}
for p in root.iterdir():
    p.chmod(0o600)
    manifest[p.name] = {'bytes': p.stat().st_size, 'sha256': hashlib.file_digest(p.open('rb'),'sha256').hexdigest(), 'mode': oct(p.stat().st_mode & 0o777)}
(root/'manifest.json').write_text(json.dumps(manifest,indent=2))
print(json.dumps({'backup':str(root),'files':manifest}))
