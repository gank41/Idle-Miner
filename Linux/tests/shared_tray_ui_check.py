"""Two actual Qt windows, isolated state; no network, engine or user settings."""
import os, sys, tempfile
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-shared-tray-ui-')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app
from PySide6.QtWidgets import QApplication
q=QApplication([]);q.setQuitOnLastWindowClosed(False)
app.QSystemTrayIcon.isSystemTrayAvailable=staticmethod(lambda:True)
a=app.Window(offline_test=True,profile='BTC');b=app.Window(offline_test=True,profile='LTC')
a.timer.stop();b.timer.stop();a.tick();b.tick();a.tick()
assert a.shared_tray.owner and not b.shared_tray.owner
assert a.tray.isVisible() and not b.tray.isVisible()
assert not a.enabled and not b.enabled
a.rebuild_tray_menu();assert all(c in a.currency_menus for c in ('BTC','LTC'))
ltc=a.currency_menus['LTC'];assert any('Stopped' in action.text() for action in ltc.actions())
assert any(action.text()=='Check for Updates…' for action in a.tray_menu.actions())
a.dispatch_currency('LTC','show_log');b.tick();assert b.tabs.currentIndex()==1
# A hidden nonowner remains accessible via the shared tray.
b.close();assert not b.quitting
# Manual checks preserve session state and explain busy, retry and offline cases.
messages=[];requests=[]
app.QMessageBox.information=lambda *args:messages.append(args[-1])
app.QMessageBox.warning=lambda *args:messages.append(args[-1])
app.check_async=lambda callback:requests.append(callback)
b.enabled=True;b.check_updates();assert b.update_busy and len(requests)==1 and b.enabled
b.check_updates();assert 'already in progress' in messages[-1]
requests[0]({'manifest':None,'error':'Offline fixture'});assert not b.update_busy and b.enabled and messages[-1]=='Offline fixture'
b.check_updates();assert 'wait a moment' in messages[-1] and len(requests)==1
b.enabled=False
# A missing coin never redirects Open to a differently selected named profile.
b.switch_currency('ETH');b.tick();spawned=[];original_popen=app.subprocess.Popen
app.subprocess.Popen=lambda *args,**kwargs:spawned.append(args)
a.open_currency('LTC');assert not spawned and 'currently showing ETH' in messages[-1]
app.subprocess.Popen=original_popen
source="import sys;sys.argv=['app.py','--profile=LTC'];import app;app.QMessageBox.information=lambda *args:print(args[-1],flush=True);app.main();assert not (app.STATE/'LTC.focus.json').exists()"
child=app.subprocess.run([sys.executable,'-c',source],cwd=app.ROOT,capture_output=True,text=True,timeout=10)
assert child.returncode==0 and 'currently showing ETH' in child.stdout,(child.stdout,child.stderr)
b.switch_currency('LTC');b.tick()
# Owner departure promotes another profile without touching the quota owner.
a.quit();b.tick();assert b.shared_tray.owner and b.tray.isVisible() and not b.quitting
# No tray fallback always makes remaining windows visible.
app.QSystemTrayIcon.isSystemTrayAvailable=staticmethod(lambda:False)
b.hide();b.tick();assert b.isVisible()
c=app.Window(offline_test=True,profile='BTC');c.timer.stop();b.tick();c.tick()
b.quit_all();assert b.quit_group is not None and not b.quitting
c.tick();assert c.quitting
b.check_quit_all();assert b.quitting
print('PASS: single tray, currency submenus, cross-profile log command, stopped launch, owner takeover, no-tray fallback',flush=True)
