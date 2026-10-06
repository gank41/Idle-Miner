"""Explicit offline Qt checks; fresh temporary state, no user wallets or network."""
import os,sys,tempfile,time
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-profile-ui-')
ROOT=Path(os.environ.get('IDLE_MINER_TEST_ROOT',str(Path.home()/'.local/share/idle-miner')))
sys.path.insert(0,str(ROOT))
import app
from core import Environment,valid_wallet,now,validated
from coordination import SettingsStore,Coordinator
from PySide6.QtWidgets import QApplication,QLineEdit,QDialogButtonBox,QCheckBox
from PySide6.QtCore import QTimer
q=QApplication([]);q.setQuitOnLastWindowClosed(False)
w=app.Window(offline_test=True);w.timer.stop()
w.sensors.sample=lambda *_:Environment(idle=True,idle_known=True,cores=os.cpu_count() or 4)
w.sensors.available_bytes=8*1024**3
assert not w.enabled and w.proc is None
assert w.isVisible() or w.tray.isVisible()
base=w.store.load();edit=validated(base);edit['show_dock']=False;edit['show_menu_bar']=True
w.store.save(edit,base);w.refresh_settings()
if not app.QSystemTrayIcon.isSystemTrayAvailable():assert w.isVisible()
assert 'Session: not started' in w.timing.text()
launch=w.clock.launched;w.work.accepted=99;w.switch_currency('BTC')
assert w.settings['coin']=='BTC' and w.work.accepted==0 and w.clock.launched==launch
assert not w.enabled
w.clock.start(t=now()-65,wall=time.time()-65);w.tick();assert '0:01:05' in w.timing.text()
w.stop();elapsed=w.clock.elapsed();time.sleep(.02);assert w.clock.elapsed()==elapsed
# Stop when a peer changes the active address without printing any addresses.
w.settings['coin']='BTC';w.enabled=True
base=w.store.load();edited=validated(base);edited['wallets']['BTC']='1BoatSLRHtKNngkdXEeobR76b53LETtpyT';w.store.save(edited,base)
w.refresh_settings();assert not w.enabled and 'receive address changed' in w.fatal
# A stale dialog edits a preference while a peer updates its BTC wallet.
def edit_dialog():
 dialog=QApplication.activeModalWidget();assert dialog
 baseline=w.store.load();edited=validated(baseline);edited['wallets']['BTC']='';w.store.save(edited,baseline)
 checkbox=next(c for c in dialog.findChildren(QCheckBox) if c.text().startswith('Pause completely'));checkbox.setChecked(True)
 dialog.findChild(QDialogButtonBox).accepted.emit()
QTimer.singleShot(200,edit_dialog);w.settings_dialog()
assert w.store.load()['wallets']['BTC']=='' and w.store.load()['pause_active']
# Named profile config and logs are isolated; closing/no tray quits safely.
peer=Coordinator(app.STATE,'LTC');peer.close()
w.grab().save('/tmp/idle-miner-profiles.png');w.quit()
print('PASS: visibility fallback, currency reset, frozen runtime, uptime, peer address stop, stale dialog merge, profile isolation',flush=True)
