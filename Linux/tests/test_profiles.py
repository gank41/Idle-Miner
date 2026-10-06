import unittest, tempfile, sys, subprocess, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import core
BTC='1BoatSLRHtKNngkdXEeobR76b53LETtpyT'
class Profiles(unittest.TestCase):
 def test_legacy_migration(self):
  s=core.validated(dict(coin='BTC',address=BTC))
  self.assertEqual(s.get('wallets'),dict(BTC=BTC,LTC='',DOGE=''))
 def test_invalid_visibility(self):
  with self.assertRaises(ValueError):core.validated(dict(show_dock=False,show_menu_bar=False))
 def test_stale_wallet_dialog_merge(self):
  from coordination import SettingsStore
  with tempfile.TemporaryDirectory() as d:
   store=SettingsStore(Path(d));old=store.load();a=store.load();a['wallets']['BTC']=BTC
   store.save(a,old);b=core.validated(old);b['idle_threads']=8
   final=store.save(b,old);self.assertEqual(final['wallets']['BTC'],BTC);self.assertEqual(final['idle_threads'],8)
 def test_clock_freezes_stop_excludes_sleep(self):
  c=core.SessionClock();c.start(t=10,wall=1000);c.sample(True,t=12);c.sample(True,t=14);c.sample(True,t=40);c.stop(t=42)
  self.assertEqual(c.elapsed(60),32);self.assertEqual(c.hashing,4)
 def test_fair_quota_reservation_and_collision(self):
  from coordination import Coordinator
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(Path(d),'default');b=Coordinator(Path(d),'BTC')
   try:
    self.assertEqual(a.update('LTC',4,4,8),4);a.reserve(4)
    self.assertEqual(b.update('BTC',4,4,8),0)
    self.assertEqual(a.update('LTC',4,4,8),2)
    a.reserve(2);self.assertEqual(b.update('BTC',4,4,8),2);b.reserve(2)
    self.assertEqual(b.update('LTC',4,4,8),0)
   finally:a.close();b.close()
 def test_profile_collision(self):
  from coordination import Coordinator
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(Path(d),'BTC')
   try:
    with self.assertRaises(BlockingIOError):Coordinator(Path(d),'BTC')
   finally:a.close()

class CrashProfiles(unittest.TestCase):
 def test_crashed_controller_keeps_capacity_until_engine_reaps(self):
  import fcntl
  from coordination import Coordinator
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(Path(d),'default');b=Coordinator(Path(d),'BTC')
   try:
    a.update('LTC',4,4,8);a.reserve(4)
    engine=open(Path(d)/'default.engine.lock','a');fcntl.flock(engine,fcntl.LOCK_EX)
    fcntl.flock(a.lock,fcntl.LOCK_UN);a.lock.close();a.closed=True
    self.assertEqual(b.update('BTC',4,4,8),0)
    engine.close();self.assertEqual(b.update('BTC',4,4,8),4)
   finally:b.close()

class RealProcessProfiles(unittest.TestCase):
 def test_dead_process_releases_shared_quota(self):
  from coordination import Coordinator
  with tempfile.TemporaryDirectory() as d:
   source="from pathlib import Path;from coordination import Coordinator;import time,sys;c=Coordinator(Path(sys.argv[1]),'LTC');print(c.update('LTC',4,4,8),flush=True);time.sleep(60)"
   child=subprocess.Popen([sys.executable,'-c',source,d],cwd=Path(__file__).resolve().parents[1],stdout=subprocess.PIPE,text=True)
   try:
    self.assertEqual(child.stdout.readline().strip(),'4')
    c=Coordinator(Path(d),'BTC')
    try:
     self.assertEqual(c.update('BTC',4,4,8),0)
     child.kill();child.wait(timeout=5)
     self.assertEqual(c.update('BTC',4,4,8),4)
    finally:c.close()
   finally:
    if child.poll() is None:child.kill();child.wait()
    child.stdout.close()
 def test_capped_peer_redistributes_fairly(self):
  from coordination import Coordinator
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(Path(d),'default');b=Coordinator(Path(d),'BTC')
   try:
    a.update('LTC',1,4,8);a.reserve(1)
    self.assertEqual(b.update('BTC',4,4,8),3)
    b.reserve(3);self.assertEqual(a.update('LTC',1,4,8),1)
   finally:a.close();b.close()

class WalletMaps(unittest.TestCase):
 def address(self,version):
  import hashlib
  payload=bytes([version])+bytes(range(20));data=payload+hashlib.sha256(hashlib.sha256(payload).digest()).digest()[:4]
  alphabet='123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';value=int.from_bytes(data,'big');result=''
  while value:value,remainder=divmod(value,58);result=alphabet[remainder]+result
  return '1'*(len(data)-len(data.lstrip(b'\0')))+result
 def test_save_all_coins_and_legacy_selected_fields(self):
  from coordination import SettingsStore
  with tempfile.TemporaryDirectory() as d:
   store=SettingsStore(Path(d));baseline=store.load();edit=core.validated(baseline)
   edit['wallets']={coin:self.address(version) for coin,version in [('BTC',0),('LTC',48),('DOGE',30)]}
   result=store.save(edit,baseline);self.assertEqual(result['wallets'],edit['wallets']);self.assertEqual(result['address'],edit['wallets']['LTC'])
   switched=core.validated(result);switched['coin']='DOGE';result=store.save(switched,result)
   self.assertEqual(result['address'],edit['wallets']['DOGE']);self.assertEqual(result['wallets'],edit['wallets'])
 def test_peer_dialog_edits_distinct_wallets(self):
  from coordination import SettingsStore
  with tempfile.TemporaryDirectory() as d:
   store=SettingsStore(Path(d));baseline=store.load();a=core.validated(baseline);b=core.validated(baseline)
   a['wallets']['BTC']=BTC;b['wallets']['DOGE']=self.address(30)
   store.save(a,baseline);result=store.save(b,baseline)
   self.assertEqual(result['wallets']['BTC'],BTC);self.assertEqual(result['wallets']['DOGE'],b['wallets']['DOGE'])
 def test_wrong_coin_wallet_never_replaces_settings(self):
  from coordination import SettingsStore
  with tempfile.TemporaryDirectory() as d:
   store=SettingsStore(Path(d));baseline=store.load();edit=core.validated(baseline);edit['wallets']['LTC']=BTC
   with self.assertRaises(ValueError):store.save(edit,baseline)
   self.assertFalse(store.path.exists())

if __name__=='__main__':unittest.main()
