"""Run the independent package and native product staging tests."""
from pathlib import Path
import unittest

root = Path(__file__).absolute().parents[2]
suite = unittest.defaultTestLoader.discover(str(root / 'tests'), pattern='test_*.py')
result = unittest.TextTestRunner(verbosity=2).run(suite)
raise SystemExit(0 if result.wasSuccessful() else 1)
