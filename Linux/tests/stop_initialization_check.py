"""Explicit actual-engine Stop during RandomX dataset setup; fresh offline profile."""
import os,sys,tempfile,time
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-init-stop-')
ROOT=Path(os.environ.get('IDLE_MINER_TEST_ROOT',str(Path.home()/'.local/share/idle-miner')))
sys.path.insert(0,str(ROOT))
import app
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication
q=QApplication([]);q.setQuitOnLastWindowClosed(False);w=app.Window(offline_test=True);w.benchmark()
started=time.monotonic();stopped=False;failure=[]
def poll():
 global stopped
 if time.monotonic()-started>40:failure.append('Stop/reap during initialization timed out');w.quit();return
 if not stopped and 'init dataset algo' in w.log.toPlainText():
  assert not w.engine_ready;w.stop();stopped=True
 if stopped and w.proc is None:
  assert w.current_threads==0 and w.coordinator.data['reserved']==0 and not w.configpath.exists()
  print('PASS: Stop during actual RandomX initialization reaps engine, releases reservation and removes config',flush=True);w.quit()
timer=QTimer();timer.timeout.connect(poll);timer.start(50)
q.exec();assert not failure,failure;assert stopped
