"""Actual Qt lifecycle tests, no engine launch/network/wallets; fresh isolated state."""
import os,sys,tempfile,time
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-clock-lifecycle-')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from PySide6.QtWidgets import QApplication
from PySide6.QtCore import QProcess
import app
from core import Environment,now
q=QApplication([]);q.setQuitOnLastWindowClosed(False);w=app.Window(offline_test=True);w.timer.stop()
w.start_engine=lambda *_:None
w.sensors.sample=lambda *_:Environment(idle=True,idle_known=True,cores=4)
w.sensors.available_bytes=8*1024**3
failures=[]
def fresh():
 w.enabled=False;w.benchmark_until=0;w.stopping=False;w.fatal='';w.change_deadline=0;w.boost_until=0;w.current_threads=0;w.engine_ready=False
 w.clock.start(t=now()-5)
def check(condition,label):
 print(('PASS: ' if condition else 'FAIL: ')+label,flush=True)
 if not condition:failures.append(label)
def frozen(label):
 value=w.clock.elapsed();time.sleep(.02);check(w.clock.started is None and w.clock.elapsed()==value,label)
# Natural completion before the70second timer must freeze the session.
fresh();w.benchmark_until=now()+60;w.engine_done(0,QProcess.ExitStatus.NormalExit)
frozen('Successful early offline completion freezes elapsed')
# A requested terminal shutdown must freeze; automatic pause must preserve elapsed.
fresh();w.fatal='Thread count mismatch';w.stopping=True;w.engine_done(0,QProcess.ExitStatus.NormalExit)
frozen('Fault-requested engine shutdown freezes elapsed')
fresh();w.enabled=True;w.stopping=True;w.engine_done(0,QProcess.ExitStatus.NormalExit)
check(w.clock.started is not None,'Automatic session pause keeps elapsed running')
fresh();w.benchmark_until=now()+60;w.stopping=True;w.engine_done(0,QProcess.ExitStatus.NormalExit)
check(w.clock.started is not None,'Temporary benchmark pause keeps elapsed running')
# READY mismatch is a terminal fault even before the child finishes stopping.
class OutputProcess:
 def readAllStandardOutput(self):return b'READY threads 2/2 huge pages 0%\n'
 def terminate(self):pass
 def deleteLater(self):pass
fresh();w.enabled=True;w.current_threads=1;w.proc=OutputProcess();w.read_engine()
frozen('READY mismatch freezes immediately');w.cleanup_engine()
# Failure to confirm a reload is terminal, independent of later reaping.
fresh();w.enabled=True;w.current_threads=1;w.change_deadline=now()-1;w.tick()
frozen('Unconfirmed thread reload freezes immediately')
# Offline safety cancellation differs from an automatic session pause.
for label,environment in [('battery',Environment(on_ac=False)),('heat',Environment(hot=True)),('memory',Environment(memory_low=True))]:
 fresh();w.benchmark_until=now()+60;w.sensors.sample=lambda *_,e=environment:e;w.tick()
 frozen('Offline '+label+' cancellation freezes elapsed')
fresh();w.enabled=True;w.sensors.sample=lambda *_:Environment(on_ac=False);w.tick()
check(w.clock.started is not None,'Automatic battery pause preserves session runtime')
# Stop during asynchronous switching must cancel the scheduled auto-resume.
fresh();w.sensors.sample=lambda *_:Environment(idle=True,idle_known=True,cores=4)
base=w.store.load();edit=dict(base,wallets=dict(base['wallets']));edit['wallets']['BTC']='1BoatSLRHtKNngkdXEeobR76b53LETtpyT';w.store.save(edit,base);w.settings=w.store.load()
w.enabled=True;w.proc=OutputProcess();w.current_threads=1
w.switch_currency('BTC');check(w.pending_resume,'Switch remembers an enabled session during asynchronous shutdown')
w.stop();check(not w.pending_resume,'Explicit Stop cancels scheduled currency auto-resume')
w.proc=None;w.cleanup_engine();w.finish_switch()
check(w.settings['coin']=='BTC' and not w.enabled,'Currency completes stopped after explicit Stop')
from PySide6.QtGui import QAction
stop_action=QAction('Stop',w);stop_action.triggered.connect(w.stop);w.pending_resume=True;stop_action.trigger()
check(not w.pending_resume,'Qt Stop action cancels scheduled resume when emitting checked arguments')
w.proc=None;w.quit();assert not failures,failures
