"""Run native Qt update resume behavior with isolated HOME and no engine/network."""
import os,subprocess,sys,unittest
from pathlib import Path
@unittest.skipUnless(sys.platform=='linux','Native Linux Qt controls required')
class UpdateResumeUI(unittest.TestCase):
 def test_resume_transaction_uses_normal_policy_and_exact_pre_stop_state(self):
  result=subprocess.run([sys.executable,str(Path(__file__).with_name('update_resume_ui_check.py'))],env={**os.environ,'QT_QPA_PLATFORM':'offscreen','PYTHONDONTWRITEBYTECODE':'1'},capture_output=True,text=True,timeout=30)
  self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
