import os,subprocess,sys,unittest
from pathlib import Path
class ClockLifecycle(unittest.TestCase):
 def test_qt_terminal_and_automatic_pause_lifecycle(self):
  result=subprocess.run([sys.executable,str(Path(__file__).with_name('clock_lifecycle_check.py'))],env={**os.environ,'QT_QPA_PLATFORM':'offscreen'},text=True,capture_output=True,timeout=20)
  self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
