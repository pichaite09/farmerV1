import copy
import unittest
from unittest.mock import patch
import activate_notifications as rollout


class ActivationSafety(unittest.TestCase):
    def test_old_api_still_running_blocks_activation(self):
        with patch.object(rollout, 'run'), patch.object(rollout, 'inspect', return_value={'State': {'Running': True}}):
            with self.assertRaisesRegex(AssertionError, 'old writer'):
                rollout.quiesce_old_writers()

    def test_runtime_parity_rejects_environment_volume_and_network_drift(self):
        api = {'Image': 'sha256:fixture', 'Config': {'Env': ['FIREBASE_PROJECT_ID=fixture', 'FIREBASE_CLIENT_EMAIL=fixture', 'FIREBASE_PRIVATE_KEY=fixture']},
               'Mounts': [{'Type': 'volume', 'Name': 'fixture_data', 'Destination': '/data/attachments', 'RW': True}],
               'NetworkSettings': {'Networks': {'private': {}, 'edge': {}}}}
        rollout.verify_runtime_parity(api, copy.deepcopy(api))
        for key, value in [('Image', 'sha256:old'), ('Config', {'Env': []}), ('Mounts', []), ('NetworkSettings', {'Networks': {'private': {}}})]:
            worker = copy.deepcopy(api)
            worker[key] = value
            with self.subTest(key=key), self.assertRaises(AssertionError):
                rollout.verify_runtime_parity(api, worker)
