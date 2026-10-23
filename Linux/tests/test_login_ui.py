"""Run native Qt login regressions with no engine/network and temporary HOME."""
import os,subprocess,sys,unittest
from pathlib import Path
@unittest.skipUnless(sys.platform=='linux','Native Linux Qt controls required')
class LoginUI(unittest.TestCase):
 def test_explicit_login_and_immediate_settings_controls(self):
  result=subprocess.run([sys.executable,str(Path(__file__).with_name('login_ui_check.py'))],env={**os.environ,'QT_QPA_PLATFORM':'offscreen','PYTHONDONTWRITEBYTECODE':'1'},capture_output=True,text=True,timeout=30)
  self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
