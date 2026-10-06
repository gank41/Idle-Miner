"""Run explicitly on a Fedora desktop; uses a fresh temporary profile and OFFLINE mining only."""
import os,sys,tempfile,shutil
from unittest.mock import patch
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-miner-verification-')
ROOT=Path.home()/'.local/share/idle-miner'
sys.path.insert(0,str(ROOT))
import app as miner
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication
from core import Environment,now,valid_wallet
q=QApplication([]);q.setQuitOnLastWindowClosed(False);w=miner.Window(offline_test=True);w.show()
checks=[];failures=[]
def check(condition,message):
 if not condition: failures.append(message);print('FAIL:',message,flush=True)
 else:checks.append(message);print('PASS:',message,flush=True)
check(not w.enabled and w.proc is None,'Startup is stopped; no wallet copied')
check(w.sensors.sample().idle_known,'GNOME Wayland idle time is readable')
miner.AUTOSTART=Path(os.environ['IDLE_MINER_STATE'])/'autostart/idle-miner.desktop'
desktop_fixture=Path(os.environ['IDLE_MINER_STATE'])/'test-launcher.desktop';desktop_fixture.write_text('[Desktop Entry]\nType=Application\nName=Idle Miner\nExec=idle-miner\n')
copy_fixture=shutil.copy2
with patch.object(miner.shutil,'copy2',side_effect=lambda _source,dest:copy_fixture(desktop_fixture,dest)):w.set_login(True)
check(miner.AUTOSTART.exists(),'Start at Login creates desktop entry')
w.set_login(False);check(not miner.AUTOSTART.exists(),'Start at Login removes only its own entry')
# Settings validation/UI through actual controls, cancel leaves profile intact.
def close_dialog():
 d=QApplication.activeModalWidget()
 if d:d.grab().save('/tmp/idle-miner-linux-settings.png');d.reject()
QTimer.singleShot(400,close_dialog);w.settings_dialog()
check(not (miner.STATE/'settings.json').exists(),'Cancel Settings preserves saved state')
w.benchmark()
check(w.proc is not None and not w.enabled,'Offline benchmark starts without enabling pool mining')
phase='startup';deadline=now()+110;original_pid=0;started_reload=0;clock_ready_at=0;reload_times=[]
def poll():
 global phase,original_pid,started_reload,clock_ready_at
 if now()>deadline:
  check(False,'Integration completed before timeout');finish();return
 if phase=='startup' and w.engine_ready and w.work.rate and w.work.rate>0:
  check(w.current_threads==1,'Offline benchmark actually uses one thread')
  check(w.work.accepted==0,'Offline work never reports earnings')
  original_pid=w.proc.processId();clock_ready_at=now()+3;phase='clock'
 elif phase=='clock' and now()>=clock_ready_at:
  check(w.clock.hashing>0,'Hashing time accumulates only after real fresh positive work')
  w.grab().save('/tmp/idle-miner-linux-hashing.png');w.timer.stop();started_reload=now();w.change_threads(2);phase='two'
 elif phase=='two' and w.engine_ready:
  reload_times.append(now()-started_reload);check(w.current_threads==2 and w.proc.processId()==original_pid,'Two-thread reload keeps the engine process')
  started_reload=now();w.change_threads(1);phase='one'
 elif phase=='one' and w.engine_ready:
  reload_times.append(now()-started_reload)
  check(w.current_threads==1 and w.proc.processId()==original_pid,'One-thread reload keeps the engine process')
  check(w.log.toPlainText().count('init dataset algo')==1,'Thread changes initialize only one RandomX dataset')
  check(all(x<5 for x in reload_times),'Thread reloads take under five seconds')
  print('Reload seconds:',reload_times,flush=True)
  w.grab().save('/tmp/idle-miner-linux-mining.png')
  w.boost_until=now()-1;w.tick();check(w.boost_until==0,'Expired boost returns to automatic')
  w.benchmark_until=now()-1;w.tick();phase='stop'
 elif phase=='stop' and w.proc is None:finish()
def finish():
 timer.stop();w.timer.stop()
 check(w.proc is None and not w.benchmark_until,'Timed benchmark stops its engine')
 check(w.clock.started is None,'Finished offline session freezes runtime')
 check(not w.configpath.exists(),'Ephemeral engine config removed')
 print(f'Integration checks: {len(checks)} passed, {len(failures)} failed',flush=True)
 w.grab().save('/tmp/idle-miner-linux.png');w.quit()
timer=QTimer();timer.timeout.connect(poll);timer.start(100)
q.exec()
sys.exit(bool(failures))
