"""SDK aliases stay checkout-owned and honor the installed platform identity."""
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from android_sdk import sdk_view
from sdk import non_android_environment


class AndroidSdkViewTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.root = self.directory / 'checkout'
        self.root.mkdir()
        self.sdk = self.directory / 'installed-sdk'
        platform = self.sdk / 'platforms/android-37.0'
        platform.mkdir(parents=True)
        (platform / 'android.jar').write_bytes(b'installed platform')
        (platform / 'source.properties').write_text('AndroidVersion.ApiLevel=37.0\n')
        (self.sdk / 'build-tools').mkdir()

    def test_alias_reuses_installed_platform_without_changing_global_sdk(self):
        view = sdk_view(self.root, self.sdk)
        self.assertEqual((view / 'platforms/android-37').resolve(), self.sdk / 'platforms/android-37.0')
        self.assertFalse((self.sdk / 'platforms/android-37').exists())
        self.assertEqual(sdk_view(self.root, self.sdk), view)
        other = self.directory / 'other-checkout'
        other.mkdir()
        self.assertNotEqual(sdk_view(other, self.sdk), view)

    def test_modified_view_and_other_checkout_symlink_are_preserved(self):
        view = sdk_view(self.root, self.sdk)
        tools = view / 'build-tools'
        tools.unlink()
        tools.mkdir()
        (tools / 'user-edit').write_text('preserve me')
        with self.assertRaisesRegex(ValueError, 'Preserving modified'):
            sdk_view(self.root, self.sdk)
        self.assertEqual((tools / 'user-edit').read_text(), 'preserve me')
        other = self.directory / 'other-checkout'
        (other / '.build').mkdir(parents=True)
        (other / '.build/android-sdk').symlink_to(view, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Preserving modified'):
            sdk_view(other, self.sdk)

    def test_incorrect_platform_identity_is_rejected(self):
        (self.sdk / 'platforms/android-37.0/source.properties').write_text('AndroidVersion.ApiLevel=36\n')
        with self.assertRaisesRegex(ValueError, 'identity differs'):
            sdk_view(self.root, self.sdk)
        self.assertFalse((self.root / '.build').exists())

    def test_non_android_compilation_does_not_require_an_installed_sdk(self):
        with patch.dict(os.environ, {'ANDROID_HOME': str(self.sdk), 'ANDROID_SDK_ROOT': str(self.sdk), 'NUXIE_IOS_ARTIFACTS': 'prepared'}):
            environment = non_android_environment()
            self.assertEqual(environment['ANDROID_HOME'], '')
            self.assertEqual(environment['ANDROID_SDK_ROOT'], '')
            self.assertEqual(environment['NUXIE_IOS_ARTIFACTS'], 'prepared')
            self.assertEqual(os.environ['ANDROID_HOME'], str(self.sdk))


if __name__ == '__main__':
    unittest.main()
