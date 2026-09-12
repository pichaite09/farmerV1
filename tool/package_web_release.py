"""Package a completed Flutter web build under a coherent immutable asset base.

Does not deploy. Keep older releases on the server for already-open tabs.
Root index.html must be no-cache; never overlay one release with another.
"""
import hashlib
from pathlib import Path
import re
import shutil
import sys


def package(source: Path, destination: Path) -> str:
    source, destination = source.resolve(), destination.resolve()
    if source == destination or source in destination.parents:
        raise ValueError('Output must be outside the input build')
    digest = hashlib.sha256()
    for path in sorted(source.rglob('*')):
        if path.is_file():
            digest.update(path.relative_to(source).as_posix().encode())
            digest.update(path.read_bytes())
    release = digest.hexdigest()[:20]
    base = f'/releases/{release}/'
    index, count = re.subn(r'<base href="[^"]*">', f'<base href="{base}">', (source / 'index.html').read_text())
    if count != 1:
        raise ValueError('Expected one Flutter base element')
    bootstrap, count = re.subn(r'"mainJsPath"\s*:\s*"main.dart.js"', f'"mainJsPath":"{base}main.dart.js"', (source / 'flutter_bootstrap.js').read_text())
    if count != 1:
        raise ValueError('Expected actual buildConfig.mainJsPath; refusing a fallback-only rewrite')
    target = destination / 'releases' / release
    if not target.exists():
        shutil.copytree(source, target)
        (target / 'flutter_bootstrap.js').write_text(bootstrap)
        (target / 'index.html').write_text(index)
    destination.mkdir(parents=True, exist_ok=True)
    # Push registration intentionally uses an absolute, stable root URL.
    # Keep this alongside the versioned build, without changing its scope.
    if (source / 'push_service_worker.js').exists():
        shutil.copy2(source / 'push_service_worker.js', destination / 'push_service_worker.js')
    temporary = destination / 'index.html.next'
    temporary.write_text(index)
    temporary.replace(destination / 'index.html')
    return release


if __name__ == '__main__':
    print(package(Path(sys.argv[1]), Path(sys.argv[2])))
