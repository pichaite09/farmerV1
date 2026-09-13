"""Run with python3 -m unittest discover -s deploy -p 'test_*.py'. No DB."""
import unittest
from pathlib import Path
import yaml


class SchedulerDeploymentContract(unittest.TestCase):
    def test_worker_shares_api_image_credentials_and_egress(self):
        services = yaml.safe_load((Path(__file__).parents[1] / 'compose.yaml').read_text())['services']
        self.assertIn('scheduler', services, 'Worker must not remain an orphan on a stale image')
        api, worker = services['api'], services['scheduler']
        self.assertEqual(worker['build'], api['build'])
        self.assertEqual(worker['image'], api['image'])
        self.assertEqual(worker['command'], ['python', '-m', 'app.scheduler'])
        for key in ('DATABASE_URL', 'FIREBASE_PROJECT_ID', 'FIREBASE_CLIENT_EMAIL', 'FIREBASE_PRIVATE_KEY'):
            self.assertEqual(worker['environment'][key], api['environment'][key])
        self.assertEqual(worker['environment'], api['environment'])
        self.assertEqual(worker['volumes'], api['volumes'])
        self.assertIn('edge', worker['networks'])
        self.assertEqual(worker['depends_on']['api']['condition'], 'service_healthy')
        self.assertIn('notifications', worker['profiles'], 'Production worker startup must be explicit')
