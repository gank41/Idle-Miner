"""Native desktop smoke check with temporary state and no mining/network."""
import os, sys, tempfile
from pathlib import Path
os.environ['IDLE_MINER_STATE']=tempfile.mkdtemp(prefix='idle-native-tray-')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app
from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication
q=QApplication([]);q.setQuitOnLastWindowClosed(False)
a=app.Window(offline_test=True,profile='BTC');b=app.Window(offline_test=True,profile='LTC')
def check():
 try:
  a.tick();b.tick();a.rebuild_tray_menu()
  available=app.QSystemTrayIcon.isSystemTrayAvailable()
  assert a.shared_tray.owner and not b.shared_tray.owner
  assert not a.enabled and not b.enabled and a.proc is None and b.proc is None
  if available:assert a.tray.isVisible() and not b.tray.isVisible()
  else:assert a.isVisible() and b.isVisible()
  a.dispatch_currency('LTC','show_log');b.tick();assert b.tabs.currentIndex()==1
  b.grab().save('/tmp/idle-miner-1.8-native.png')
  print('PASS: native desktop; tray available='+str(available)+'; one owner; two accessible stopped windows; cross-currency Engine Log',flush=True)
  a.quit();b.quit()
 except Exception:
  import traceback;traceback.print_exc();os._exit(1)
QTimer.singleShot(1000,check);QTimer.singleShot(15000,lambda:os._exit(2));q.exec()
