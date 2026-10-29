"""Native Qt update hooks/startup; isolated settings and no mining or network."""
import os,sys,tempfile
from pathlib import Path
from unittest.mock import patch
home=tempfile.TemporaryDirectory(prefix='idle-update-resume-ui-');os.environ['HOME']=home.name;os.environ['IDLE_MINER_STATE']=str(Path(home.name)/'state')
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import app,updates
from core import validated,Environment
from PySide6.QtWidgets import QApplication
q=QApplication([]);q.setQuitOnLastWindowClosed(False)
w=app.Window(offline_test=True);w.timer.stop();w.sensors.sample=lambda *_:Environment(on_ac=False);w.sensors.available_bytes=0
base=w.store.load();edited=validated(base);edited['wallets']=dict(BTC='1BoatSLRHtKNngkdXEeobR76b53LETtpyT',LTC='LKDyUEtTR1HXamkiEphisSiBJu6o3ZPE34',DOGE='D597kHXGdkwkryF9oGhz9Bp1ypTpD1u99Z',ETH='0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed');edited['start_mining_at_login']=True;w.store.save(edited,base);w.refresh_settings()
app.AUTOSTART.parent.mkdir(parents=True);app.AUTOSTART.write_text('[Desktop Entry]\nType=Application\nExec=fixture --login-startup\n')
original=(app.STATE/'settings.json').read_bytes();root=Path(home.name)/'custom installation';root.mkdir()
with patch.object(app,'ROOT',root):
 # Actual OS login takes precedence over update markers, valid or invalid.
 for login_mining in (False,True):
  for valid in (False,True):
   baseline=w.store.load();edited=validated(baseline);edited['start_mining_at_login']=login_mining;w.store.save(edited,baseline);w.refresh_settings()
   marker='invalid'
   if valid:
    (root/'core.py').write_text("VERSION = '0.1'\nBUILD = 1\n")
    row=dict(profile='default',coin='ETH',pid=os.getpid(),nonce=w.shared_tray.nonce)
    marker=updates.begin_resume(app.STATE,root,'0.1',1,app.VERSION,app.BUILD,[row],'default')
    assert updates.acknowledge_resume(app.STATE,root,marker,'default',os.getpid(),w.shared_tray.nonce,'ETH',True)
    plan=updates.finalize_resume(app.STATE,root,marker,timeout=0)
    (root/'core.py').write_text('VERSION = '+repr(app.VERSION)+'\nBUILD = '+str(app.BUILD)+'\n');updates.publish_resume(app.STATE,root,plan)
   with patch('app.subprocess.Popen') as launch:
    w.apply_startup(['--resume-update='+marker,'--login-startup'])
    assert w.enabled==login_mining,(login_mining,valid,w.enabled)
    assert launch.call_count==(3 if login_mining else 0)
    assert all('--start-mining' in c.args[0] and not any(a.startswith('--resume-update=') for a in c.args[0]) for c in launch.call_args_list)
   if valid:assert not updates.receipt_path(app.STATE,marker).exists(),'OS login must discard update intent'
   w.stop()
 original=(app.STATE/'settings.json').read_bytes()
 w.apply_startup([]);assert not w.enabled
 w.apply_startup(['--resume-update=invalid']);assert not w.enabled
 # Simulate a switched default profile, a manually stopped BTC, and a paused LTC.
 (root/'core.py').write_text("VERSION = '0.1'\nBUILD = 1\n")
 rows=[dict(profile=p,coin=c,pid=os.getpid(),nonce=n) for p,c,n in [('default','ETH',w.shared_tray.nonce),('BTC','DOGE','2'*32),('LTC','LTC','3'*32)]]
 token=updates.begin_resume(app.STATE,root,'0.1',1,app.VERSION,app.BUILD,rows,'default')
 w.settings['coin']='ETH';w.settings['address']=w.settings['wallets']['ETH'];w.enabled=True;w.boost_until=99999
 assert w.acknowledge_update(token)
 for row,enabled in zip(rows[1:],[False,True]):assert updates.acknowledge_resume(app.STATE,root,token,row['profile'],row['pid'],row['nonce'],row['coin'],enabled)
 plan=updates.finalize_resume(app.STATE,root,token,timeout=0);w.stop();assert w.boost_until==0 and w.benchmark_until==0
 (root/'core.py').write_text('VERSION = '+repr(app.VERSION)+'\nBUILD = '+str(app.BUILD)+'\n');updates.publish_resume(app.STATE,root,plan)
 with patch('app.subprocess.Popen') as launch:
  w.apply_startup(['--resume-update='+token]);assert w.enabled and w.settings['coin']=='ETH' and w.proc is None
  assert w.boost_until==0 and w.benchmark_until==0;assert launch.call_count==2
  commands=[c.args[0] for c in launch.call_args_list]
  assert all('--resume-update='+token in args and '--start-mining' not in args and '--login-startup' not in args for args in commands)
  assert {'--profile=BTC','--profile=LTC'}=={a for args in commands for a in args if a.startswith('--profile=')}
 w.stop();w.apply_startup(['--resume-update='+token]);assert not w.enabled
 for profile,expected_coin,expected_enabled in [('BTC','DOGE',False),('LTC','LTC',True)]:
  peer=app.Window(offline_test=True,profile=profile);peer.timer.stop();peer.sensors.sample=lambda *_:Environment(on_ac=False);peer.sensors.available_bytes=0
  peer.apply_startup(['--resume-update='+token]);assert peer.settings['coin']==expected_coin and peer.enabled==expected_enabled and peer.proc is None
  assert peer.boost_until==0 and peer.benchmark_until==0
  peer.quit()
 assert (app.STATE/'settings.json').read_bytes()==original
 # A user Stop before the quit hook overrides a previously enabled summary.
 (root/'core.py').write_text("VERSION = '0.1'\nBUILD = 1\n");token=updates.begin_resume(app.STATE,root,'0.1',1,app.VERSION,app.BUILD,[rows[0]],'default')
 w.enabled=True;w.stop();assert w.acknowledge_update(token)
 assert updates.finalize_resume(app.STATE,root,token,timeout=0)['targets'][0]['enabled'] is False
 # Invalid tokens do not quit an existing currency.
 w.quit_for_update('bad');assert not w.quitting
 # Canceled preparation leaves all sessions untouched and never starts a helper.
 import threading
 workspace=Path(home.name)/'cancelled';workspace.mkdir();w.update_cancel.set()
 with patch('app.subprocess.Popen') as launch:
  w.update_prepared(dict(workspace=str(workspace),stage=str(workspace/'stage')));assert not launch.called and not w.quitting
 # Native tray delivery runs the acknowledging hook before Stop and Quit.
 w.update_cancel.clear();w.shared_tray.publish('ETH',{})
 token=updates.begin_resume(app.STATE,root,'0.1',1,app.VERSION,app.BUILD,[rows[0]],'default')
 target=rows[0];target['coin']='ETH';assert w.shared_tray.send(target,'quit-update:'+token)
 w.enabled=True;w.tick();assert w.quitting
 assert updates.finalize_resume(app.STATE,root,token,timeout=0)['targets'][0]['enabled'] is True
home.cleanup();print('PASS: exact switched-profile restore, enabled battery pause, stopped peer, single use, no boost/benchmark, settings bytes, manual/login distinction, cancel, native pre-stop quit hook')
