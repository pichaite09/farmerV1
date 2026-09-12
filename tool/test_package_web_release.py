"""Tests for coherent immutable Flutter release asset packaging."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

class ReleaseTest(unittest.TestCase):
    def test_main_and_font_share_release_base(self):
        spec = importlib.util.spec_from_file_location('release', Path(__file__).with_name('package_web_release.py'))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            src = root / 'source'; src.mkdir()
            (src / 'index.html').write_text('<base href="/"><script src="flutter_bootstrap.js"></script>')
            (src / 'flutter_bootstrap.js').write_text('_flutter.buildConfig={"builds":[{"mainJsPath":"main.dart.js"}]};')
            (src / 'main.dart.js').write_text('test bundle')
            (src / 'assets/fonts').mkdir(parents=True)
            (src / 'assets/fonts/MaterialIcons-Regular.otf').write_bytes(b'test font')
            destination = root / 'site'
            release = module.package(src, destination)
            self.assertIn(f'<base href="/releases/{release}/">', (destination / 'index.html').read_text())
            bundle = destination / 'releases' / release
            self.assertIn(f'"mainJsPath":"/releases/{release}/main.dart.js"', (bundle / 'flutter_bootstrap.js').read_text())
            self.assertEqual((bundle / 'assets/fonts/MaterialIcons-Regular.otf').read_bytes(), b'test font')
            (src / 'assets/fonts/MaterialIcons-Regular.otf').write_bytes(b'new font')
            self.assertNotEqual(module.package(src, destination), release)

if __name__ == '__main__': unittest.main()
