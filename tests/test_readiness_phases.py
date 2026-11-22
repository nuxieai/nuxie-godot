import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
from types import SimpleNamespace
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('godot_readiness',ROOT/'scripts/check.py')
check=importlib.util.module_from_spec(spec);spec.loader.exec_module(check)

class ReadinessPhaseTests(unittest.TestCase):
    def execute(self,phase):
        calls=[]
        with patch.object(sys,'argv',['check.py','--phase',phase]),patch.dict(sys.modules,{'pool':SimpleNamespace(dispatch=lambda *a:None)}),patch.object(check,'run',side_effect=calls.append),patch.object(check,'portable',side_effect=lambda:calls.append(['portable'])):
            check.main()
        return calls

    def test_android_phase_does_not_repeat_godot_or_apple_checks(self):
        self.assertEqual(self.execute('android'),[['python3','scripts/bazel/sdk.py','test-android'],['python3','scripts/prepare-native.py','--platform','android'],['./gradlew',':android-plugin:lint']])

    def test_apple_phase_has_only_apple_preparation_and_check(self):
        self.assertEqual(self.execute('ios'),[['python3','scripts/prepare-native.py','--platform','ios'],['python3','scripts/check-ios.py']])

    def test_portable_phase_does_not_prepare_native_products(self):
        self.assertEqual(self.execute('portable'),[['portable']])
