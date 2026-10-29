import os,subprocess,sys,unittest
from pathlib import Path
@unittest.skipUnless(sys.platform=='linux','Native Linux Qt controls required')
class ScheduledUpdateUI(unittest.TestCase):
 def test_native_scheduled_controls_and_background_safety(self):
  result=subprocess.run([sys.executable,str(Path(__file__).with_name('scheduled_update_ui_check.py'))],env={**os.environ,'QT_QPA_PLATFORM':'offscreen','PYTHONDONTWRITEBYTECODE':'1'},capture_output=True,text=True,timeout=30)
  self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
