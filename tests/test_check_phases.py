"""Execute the check dispatcher against a recording pool transport."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('pool_check_phases', ROOT / 'scripts/pool.py')
POOL = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(POOL)


class CheckPhaseTests(unittest.TestCase):
    def test_full_check_places_each_phase_independently_without_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);helper=home/'.local/share/nuxie-homelab/sdk-task.py'
            helper.parent.mkdir(parents=True)
            log=home/'requests.jsonl'
            helper.write_text('''import json, os
from pathlib import Path
def route(root, arguments, **kwargs):
    with Path(os.environ['PHASE_LOG']).open('a') as stream:
        stream.write(json.dumps({'args':arguments,'platform':kwargs['platform'],'requirements':kwargs['requirements']})+'\\n')
    return 9 if arguments[-1]==os.environ.get('FAIL_PHASE') else 0
''')
            with patch.dict(os.environ,{'PHASE_LOG':str(log)},clear=True),patch.object(Path,'home',return_value=home):
                self.assertEqual(POOL.dispatch('check',[]),0)
            requests=[json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual([r['args'] for r in requests],[['check','--phase',name] for name in POOL.CHECK_PHASES])
            self.assertEqual(requests[0]['platform'],'portable')
            self.assertNotIn('xcode',requests[0]['requirements'])
            self.assertEqual(next(r for r in requests if r['args'][-1]=='ios')['platform'],'macos')
            self.assertEqual(next(r for r in requests if r['args'][-1]=='android')['platform'],'portable')
            log.unlink()
            with patch.dict(os.environ,{'PHASE_LOG':str(log),'FAIL_PHASE':'android'},clear=True),patch.object(Path,'home',return_value=home):
                self.assertEqual(POOL.dispatch('check',[]),9)
            self.assertEqual(len(log.read_text().splitlines()),2)

    def test_ios_does_not_require_android_and_portable_does_not_require_apple(self):
        platform,tools=POOL.selection('check',['--phase','ios'])
        self.assertEqual(platform,'macos');self.assertIn('xcode',tools);self.assertNotIn('android',tools)
        platform,tools=POOL.selection('check',['--phase','portable'])
        self.assertEqual(platform,'portable');self.assertNotIn('xcode',tools);self.assertNotIn('android',tools)
        with self.assertRaises(ValueError):POOL.selection('check',['--phase','missing'])

    def test_nested_or_explicit_local_check_retains_the_original_local_frontend(self):
        for env in ({'_NUXIE_POOL_NESTED':'1'},{'NUXIE_EXECUTION':'local'},{'NUXIE_HOMELAB':'0'}):
            with patch.dict(os.environ,env,clear=True):self.assertIsNone(POOL.dispatch('check',[]))


if __name__ == '__main__': unittest.main()
