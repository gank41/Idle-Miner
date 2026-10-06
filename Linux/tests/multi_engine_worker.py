"""Real Qt controller/engine harness. Fresh state supplied by parent; every engine is offline."""
import os,sys,time,json
from pathlib import Path
ROOT=Path(os.environ.get('IDLE_MINER_TEST_ROOT',str(Path.home()/'.local/share/idle-miner')))
sys.path.insert(0,str(ROOT))
import app,core
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import QTimer
profile=sys.argv[1];coin='LTC' if profile=='default' else profile
q=QApplication([]);q.setQuitOnLastWindowClosed(False);w=app.Window(offline_test=True,profile=profile);w.timer.stop()
w.settings['idle_threads']=4
w.sensors.sample=lambda *_:core.Environment(idle=True,idle_known=True,cores=os.cpu_count() or 4)
w.sensors.available_bytes=8*1024**3
# Test-only override sends no pool traffic, irrespective of public receive fixture.
def offline_config(s,n,benchmark=False):
 data=core.config(s,n,True);data['benchmark']['size']='10M';return data
app.config=offline_config
w.enabled=True;w.clock.start();w.tick()
last=None;stopped=False;deadline=time.monotonic()+200
stopfile=Path(os.environ['IDLE_MINER_STATE'])/(profile+'.stop')
def poll():
 global last,stopped
 if stopfile.exists() and not stopped:w.stop();stopped=True
 else:w.tick()
 snapshot=(w.current_threads,w.engine_ready,w.stopping,w.proc.processId() if w.proc else 0,w.coordinator.data['reserved'],w.fatal)
 if snapshot!=last:
  print(json.dumps(dict(profile=profile,threads=snapshot[0],ready=snapshot[1],stopping=snapshot[2],pid=snapshot[3],reserved=snapshot[4],fatal=snapshot[5])),flush=True);last=snapshot
 if (stopped and w.proc is None) or time.monotonic()>deadline:w.quit()
timer=QTimer();timer.timeout.connect(poll);timer.start(200)
q.exec()
