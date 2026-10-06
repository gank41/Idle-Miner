import os,sys,tempfile
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-guard-')
sys.path.insert(0,str(Path.home()/'.local/share/idle-miner'))
from PySide6.QtWidgets import QApplication
from core import Environment,now
import app
q=QApplication([]);w=app.Window(offline_test=True)
w.sensors.sample=lambda *_:Environment(idle=True,idle_known=True,cores=8)
w.sensors.available_bytes=2*1024**3
w.benchmark_until=now()+70;w.tick()
assert w.proc is None and w.desired==0
assert '3 GB' in w.state_label.text()
w.stop();w.quit()
print('PASS: insufficient startup memory does not launch RandomX')
