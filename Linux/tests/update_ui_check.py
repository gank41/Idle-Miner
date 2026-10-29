"""Native Qt updater presentation; no update network, engine or real settings."""
import os,sys,tempfile
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-update-ui-')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app
from PySide6.QtWidgets import QApplication,QPushButton
q=QApplication([]);q.setQuitOnLastWindowClosed(False)
w=app.Window(offline_test=True);w.timer.stop();requests=[];app.check_async=lambda callback:requests.append(callback)
w.check_updates();assert w.update_busy and len(requests)==1
assert w.update_dialog.isVisible();assert app.VERSION in w.update_versions.text()
release=dict(version='2.0',build=99,releaseNotesText='<b>Plain text</b>\nFixed updates.',url='https://idleminer.app/downloads/v2.0/Idle-Miner-2.0-Linux.tar.gz',sha256='a'*64,length=1,edSignature='A'*86+'==')
requests[0]({'manifest':release,'error':''});assert not w.update_busy
assert w.update_notes.toPlainText()=='<b>Plain text</b>\nFixed updates.'
assert '2.0' in w.update_versions.text()
buttons=[b.text() for b in w.update_dialog.findChildren(QPushButton)];assert sorted(buttons)==['Close','Download and Install Now'],buttons
assert w.update_install.isEnabled()
w.update_result({'manifest':dict(release,version=app.VERSION,build=app.BUILD),'error':''});assert not w.update_install.isEnabled();assert 'up to date' in w.update_status.text()
w.update_result({'manifest':None,'error':'Offline fixture'});assert 'Offline fixture' in w.update_status.text();assert not w.update_install.isEnabled()
w.update_preparing=True;w.update_cancel.clear();w.quit();assert not w.quitting and w.update_cancel.is_set()
w.update_failed('Cancelled fixture');w.update_dialog.close();w.quit()
print('PASS: updater installed/latest versions, inline plain release notes, Close and Install only, same-version and offline states',flush=True)
