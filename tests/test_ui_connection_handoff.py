"""Run the review snapshot's static checks through existing unittest discovery."""
from pathlib import Path
import subprocess
import sys
import unittest

class UiConnectionHandoffTest(unittest.TestCase):
    def test_review_snapshot_is_complete_and_private_data_free(self):
        root=Path(__file__).resolve().parents[1]
        result=subprocess.run([sys.executable,'-B',str(root/'tests/check_ui_connection_handoff.py')],
                              cwd=root,capture_output=True,text=True,encoding='utf-8',timeout=30)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertIn('"cameraAccess": false',result.stdout)

if __name__=='__main__':unittest.main()
