"""Native Qt automatic checks, isolated HOME/state and fully stubbed transport."""
import os,sys,tempfile,time
from pathlib import Path
from unittest.mock import patch
home=tempfile.TemporaryDirectory(prefix='idle-scheduled-ui-');os.environ['HOME']=home.name;os.environ['IDLE_MINER_STATE']=str(Path(home.name)/'state')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from PySide6.QtWidgets import QApplication,QCheckBox,QComboBox,QDialogButtonBox,QLabel
from PySide6.QtCore import QTimer,Qt
from PySide6.QtGui import QColor,QPalette
import app
q=QApplication([]);q.setQuitOnLastWindowClosed(False)
w=app.Window(offline_test=True);w.timer.stop()
assert hasattr(w,'automatic_updates'),'Background signed scheduling is missing'
w.automatic_timer.stop();assert not w.store.path.exists();assert not (app.STATE/'automatic-updates.json').exists()
failures=[]
def settings_controls():
 try:
  dialog=QApplication.activeModalWidget();checks=dialog.findChildren(QCheckBox)
  automatic=next(c for c in checks if c.text()=='Automatically check for updates')
  mine=next(c for c in checks if c.text()=='Start at Login and Start Mining configured currencies')
  assert checks.index(automatic)==checks.index(mine)+1
  frequency=dialog.findChild(QComboBox,'automaticUpdateFrequency');assert not automatic.isChecked() and not frequency.isEnabled()
  assert [frequency.itemText(i) for i in range(frequency.count())]==['Daily','Weekly']
  automatic.click();assert frequency.isEnabled() and w.store.load()['automatic_update_checks']
  frequency.setCurrentIndex(1);assert w.store.load()['update_check_frequency']=='weekly'
  dialog.reject()
 except BaseException as exc:failures.append(exc);QApplication.activeModalWidget().reject()
with patch.object(w,'scheduled_update_tick'):
 QTimer.singleShot(20,settings_controls);w.settings_dialog()
assert not failures,failures
assert w.store.load()['automatic_update_checks'],'Cancel preserves immediately applied scheduling opt-in'
requests=[];app.check_async=lambda callback:requests.append(callback)
w.check_updates();assert len(requests)==1
footer=w.update_dialog.findChild(QCheckBox,'automaticUpdateChecks');frequency=w.update_dialog.findChild(QComboBox,'automaticUpdateFrequency')
assert footer.isChecked() and frequency.currentText()=='Weekly'
assert w.update_dialog.findChild(QLabel,'updateBrandIcon').pixmap() is not None
assert w.update_dialog.findChild(QLabel,'updateBrandTitle').text()=='Idle Miner Updates'
manual_cancel=w.update_cancel;manual_last=w.update_last
notifications=[];w.notify_available_update=lambda release:notifications.append(release)
release=dict(version='2.0',build=99,releaseNotesText='Notes',url='https://idleminer.app/downloads/v2.0/Idle-Miner-2.0-Linux.tar.gz',sha256='a'*64,length=1,edSignature='A'*86+'==')
def pump():
 deadline=time.monotonic()+3
 while w.automatic_busy and time.monotonic()<deadline:q.processEvents();time.sleep(.005)
 assert not w.automatic_busy
# Finish manual result, then run automatic discovery without modifying its controls/cancel/throttle.
requests.pop()({'manifest':dict(release,version=app.VERSION,build=app.BUILD),'error':''})
with patch.object(app,'threading',wraps=app.threading),patch('updates.fetch_manifest',return_value=release),patch.object(w,'stop',side_effect=AssertionError('Automatic checks must not stop mining')):
 w.scheduled_update_tick();pump()
assert len(notifications)==1 and w.update_last==manual_last and w.update_cancel is manual_cancel and not manual_cancel.is_set()
assert 'up to date' in w.update_status.text(),'Background must not overwrite a manual dialog result'
assert w.update_menu_title()=='Update Available: 2.0 (99)…'
with patch('updates.fetch_manifest',side_effect=AssertionError('Not due')):
 w.scheduled_update_tick();pump()
assert len(notifications)==1
footer.click();assert not w.store.load()['automatic_update_checks'] and not frequency.isEnabled()
with patch('updates.fetch_manifest',side_effect=AssertionError('Disabled')):w.scheduled_update_tick();assert not w.automatic_busy
# Peer preference changes synchronize into the open footer without wallet/login mutation.
baseline=w.store.load();w.store.save({**baseline,'automatic_update_checks':True,'update_check_frequency':'daily'},baseline)
w.sync_automatic_controls(w.update_dialog);assert footer.isChecked() and frequency.currentText()=='Daily'
# Native palette semantics: no forced stylesheet, readable system colors in light and dark.
for dark in (False,True):
 palette=QPalette();palette.setColor(QPalette.ColorRole.Window,QColor('#202020' if dark else '#ffffff'));palette.setColor(QPalette.ColorRole.WindowText,QColor('#ffffff' if dark else '#202020'));palette.setColor(QPalette.ColorRole.Base,QColor('#202020' if dark else '#ffffff'));palette.setColor(QPalette.ColorRole.Text,QColor('#ffffff' if dark else '#202020'));q.setPalette(palette);q.processEvents()
 assert not w.update_dialog.styleSheet() and not w.update_status.styleSheet()
 assert w.update_status.palette().color(QPalette.ColorRole.WindowText).lightness()>(128 if dark else -1)
 w.update_dialog.grab().save(str(Path(home.name)/('dark.png' if dark else 'light.png')))
w.update_dialog.close();w.quit();home.cleanup()
print('PASS: native settings/footer immediate opt-in and sync, branded semantic palettes, silent signed background discovery, due/dedup/off, no mining stop/manual interruption')
