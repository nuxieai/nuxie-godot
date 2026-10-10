"""Publication stays isolated and refuses unsafe compiler product archives."""
from pathlib import Path
import tempfile
import unittest
import zipfile
from sdk import extract_archive, publish_tree

class SDKPublicationTests(unittest.TestCase):
    def test_publication_copies_products_without_changing_compiler_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler, checkout = root / 'compiler-cache', root / 'checkout/artifacts'
            compiler.mkdir()
            source = compiler / 'product'
            source.write_text('compiled bytes')
            source.chmod(0o444)
            publish_tree(compiler, checkout)
            self.assertEqual(source.stat().st_mode & 0o777, 0o444)
            self.assertEqual((checkout / 'product').stat().st_mode & 0o777, 0o644)
            self.assertEqual((checkout / 'product').read_text(), 'compiled bytes')
            other = root / 'other-checkout/artifacts'
            other.parent.mkdir()
            other.symlink_to(checkout, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, 'Preserving publication symlink'):
                publish_tree(compiler, other)
            self.assertEqual((checkout / 'product').read_text(), 'compiled bytes')

    def test_traversal_and_symlink_archive_members_fail_before_extraction(self):
        for name, mode, content in [('..\\outside', 0, b'file'), ('../outside', 0, b'file'), ('/outside', 0, b'file'), ('framework/link', 0o120777, b'../../outside')]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                archive = root / 'compiled.zip'
                with zipfile.ZipFile(archive, 'w') as compressed:
                    entry = zipfile.ZipInfo(name)
                    entry.external_attr = mode << 16
                    compressed.writestr(entry, content)
                with self.assertRaises(ValueError):
                    extract_archive(archive, root / 'staged')
                self.assertFalse((root / 'staged').exists())

if __name__ == '__main__':
    unittest.main()
