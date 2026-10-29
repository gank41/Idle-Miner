"""Native Qt updater presentation; no update network, engine or real settings."""
import os,sys,tempfile
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-update-ui-')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app
from PySide6.QtCore import Qt
from PySide6.QtWidgets import QApplication,QPushButton,QToolButton
q=QApplication([]);q.setQuitOnLastWindowClosed(False)
w=app.Window(offline_test=True);w.timer.stop();requests=[];app.check_async=lambda callback:requests.append(callback)
w.check_updates();assert w.update_busy and len(requests)==1
assert w.update_dialog.isVisible();assert app.VERSION in w.update_versions.text()
assert w.update_versions.text().splitlines()==[f'Installed: Idle Miner {app.VERSION} ({app.BUILD})','Latest: checking…'],'Installed/latest versions must be separate readable lines'
assert not w.update_notes.isVisible(),'Checking must hide release notes'
assert not w.update_install.isVisible(),'Checking must hide installation action'
release=dict(version='2.0',build=99,releaseNotesText='<b>Plain text</b>\nFixed updates.',url='https://idleminer.app/downloads/v2.0/Idle-Miner-2.0-Linux.tar.gz',sha256='a'*64,length=1,edSignature='A'*86+'==')
requests[0]({'manifest':release,'error':''});assert not w.update_busy
assert w.update_notes.toPlainText()=='<b>Plain text</b>\nFixed updates.'
assert '2.0' in w.update_versions.text()
buttons=[b.text() for b in w.update_dialog.findChildren(QPushButton) if b.isVisible()];assert sorted(buttons)==['Close','Download and Install Now'],buttons
assert w.update_install.isEnabled() and w.update_notes.isVisible()
notes_button=next(b for b in w.update_dialog.findChildren(QToolButton) if b.text()=='Release Notes')
assert notes_button.isChecked() and notes_button.arrowType()==Qt.ArrowType.DownArrow
q.processEvents();expanded_height=w.update_dialog.height()
w.update_result({'manifest':dict(release,version=app.VERSION,build=app.BUILD),'error':''});q.processEvents()
assert not w.update_install.isVisible() and not w.update_install.isEnabled();assert 'up to date' in w.update_status.text()
assert notes_button.isVisible() and not notes_button.isChecked()
assert not w.update_notes.isVisible(),'Current release notes should start collapsed'
assert w.update_dialog.height()<expanded_height,'Up-to-date dialog should shrink after hiding release notes'
notes_button.click();q.processEvents()
assert w.update_notes.isVisible() and notes_button.arrowType()==Qt.ArrowType.DownArrow
assert w.update_notes.toPlainText()=='<b>Plain text</b>\nFixed updates.'
notes_button.click();assert not w.update_notes.isVisible() and notes_button.arrowType()==Qt.ArrowType.RightArrow
# Rechecking after an expanded result must discard the previous disclosure state.
notes_button.click();w.update_dialog.close();w.update_last=0;w.check_updates()
assert len(requests)==2 and w.update_busy
assert not w.update_notes.isVisible() and not w.update_install.isVisible()
assert not any(b.isVisible() for b in w.update_dialog.findChildren(QToolButton))
requests[1]({'manifest':None,'error':'Offline fixture <b>text</b>'});q.processEvents()
assert 'Offline fixture <b>text</b>' in w.update_status.text();assert w.update_status.textFormat()==Qt.TextFormat.PlainText
assert not w.update_install.isVisible() and not w.update_notes.isVisible()
assert not any(b.isVisible() for b in w.update_dialog.findChildren(QToolButton))
# Older releases cannot offer installation; empty notes have no disclosure.
w.update_result({'manifest':dict(release,version='1.0',build=1,releaseNotesText=''),'error':''})
assert not w.update_install.isVisible() and not w.update_notes.isVisible()
assert not any(b.isVisible() for b in w.update_dialog.findChildren(QToolButton))
w.update_result({'manifest':dict(release,edSignature='invalid'),'error':''})
assert not w.update_install.isVisible() and not w.update_notes.isVisible()
assert not any(b.isVisible() for b in w.update_dialog.findChildren(QToolButton))
# A fresh signed available release keeps the installation path and expanded notes.
w.update_result({'manifest':release,'error':''});assert w.update_install.isVisible() and w.update_install.isEnabled() and w.update_notes.isVisible()
w.update_preparing=True;w.update_cancel.clear();w.quit();assert not w.quitting and w.update_cancel.is_set()
w.update_failed('Cancelled fixture');assert 'Cancelled fixture' in w.update_status.text()
assert not w.update_notes.isVisible() and not w.update_notes_toggle.isVisible()
w.update_dialog.close();w.quit()
print('PASS: compact checking/current/error states, expandable inert release notes, fresh-check reset, signed available installation and cancellation',flush=True)
