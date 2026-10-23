"""Real Qt controls/startup policy with temporary HOME and no engine or network."""
import os,sys,tempfile
from pathlib import Path
from unittest.mock import patch
home=tempfile.TemporaryDirectory(prefix='idle-login-ui-');os.environ['HOME']=home.name;os.environ['IDLE_MINER_STATE']=str(Path(home.name)/'state')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from PySide6.QtWidgets import QApplication,QCheckBox,QDialogButtonBox,QLineEdit
from PySide6.QtCore import QTimer
import app
from core import validated,Environment
q=QApplication([]);q.setQuitOnLastWindowClosed(False)
w=app.Window(offline_test=True);w.timer.stop();w.sensors.sample=lambda *_:Environment(on_ac=False);w.sensors.available_bytes=0
entry=Path(home.name)/'.local/share/applications/idle-miner.desktop';entry.parent.mkdir(parents=True);entry.write_text('[Desktop Entry]\nType=Application\nExec="/tmp/test app"\n')
base=w.store.load();edited=validated(base);edited['wallets']['BTC']='1BoatSLRHtKNngkdXEeobR76b53LETtpyT';edited['wallets']['ETH']='0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';w.store.save(edited,base);w.refresh_settings()
assert not w.enabled
# Regression: existing Start at Login and manual launches stay stopped.
w.apply_startup([]);assert not w.enabled
w.set_login(True);w.apply_startup(['--login-startup']);assert not w.enabled
failures=[]
def dialog_check():
 try:
  dialog=QApplication.activeModalWidget();checks=dialog.findChildren(QCheckBox)
  login=next(c for c in checks if c.text()=='Start at Login')
  mine=next(c for c in checks if c.text()=='Start at Login and Start Mining configured currencies')
  assert checks.index(mine)==checks.index(login)+1 and mine.isEnabled() and not mine.isChecked()
  assert len(dialog.findChildren(QLineEdit))==4
  assert dialog.height()<=dialog.screen().availableGeometry().height(),('Settings must fit desktop',dialog.size())
  mine.click();assert w.store.load()['start_mining_at_login']
  dialog.findChild(QDialogButtonBox).accepted.emit()
 except BaseException as e:failures.append(e);QApplication.activeModalWidget().reject()
QTimer.singleShot(20,dialog_check);w.settings_dialog();assert not failures,failures
assert w.store.load()['start_mining_at_login'],'Saving a stale dialog must preserve immediate checkbox change'
with patch('app.subprocess.Popen') as launch:
 w.apply_startup([]);assert not w.enabled
 w.apply_startup(['--login-startup']);assert w.enabled and w.settings['coin']=='BTC' and w.proc is None
 args=launch.call_args[0][0];assert '--profile=ETH' in args and '--start-mining' in args and '--login-startup' not in args and '--show-stats' not in args
 assert launch.call_count==1
w.stop();w.set_login(False);assert not w.store.load()['start_mining_at_login'] and not app.AUTOSTART.exists()
def disabled_dialog():
 try:
  dialog=QApplication.activeModalWidget();checks=dialog.findChildren(QCheckBox)
  mine=next(c for c in checks if c.text()=='Start at Login and Start Mining configured currencies')
  assert not mine.isEnabled() and not mine.isChecked();dialog.reject()
 except BaseException as e:failures.append(e);QApplication.activeModalWidget().reject()
QTimer.singleShot(20,disabled_dialog);w.settings_dialog();assert not failures,failures
w.quit();home.cleanup();print('PASS: actual Qt manual/login controls, four wallets, immediate opt-in/stale-save, selective child launch, battery pause and parent-off clearing')
