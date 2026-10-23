"""ETH receive addresses and explicit login mining without user state/network."""
import os, subprocess, sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import core
from coordination import SettingsStore, Coordinator
BTC='1BoatSLRHtKNngkdXEeobR76b53LETtpyT'
ETH='0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'
# Published EIP-55 examples, independently specified: https://eips.ethereum.org/EIPS/eip-55
VECTORS=('0x52908400098527886E0F7030069857D2E4169EE7','0x8617E340B3D01FA5F11F306F4090FD50E238070D','0xde709f2102306220921060314715629080e2fb77','0x27b1fdb04752bbc536007a920d24acb045561c26','0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed','0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359','0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB','0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb')
class Ethereum(unittest.TestCase):
 def test_eip55_and_uniform_case(self):
  for address in VECTORS:
   with self.subTest(address=address):
    self.assertTrue(core.valid_wallet(address,'ETH'))
    self.assertTrue(core.valid_wallet('0x'+address[2:].lower(),'ETH'))
    self.assertTrue(core.valid_wallet('0x'+address[2:].upper(),'ETH'))
 def test_rejects_invalid_checksum_shape_zero_uri(self):
  for bad in ('0x'+'0'*40,ETH[:-1],ETH+'0','0x'+'g'*40,'ethereum:'+ETH,ETH+' ',ETH+'.worker','0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'):
   with self.subTest(address=bad):self.assertFalse(core.valid_wallet(bad,'ETH'))
 def test_eth_config_and_native_pool_account(self):
  s=core.validated(dict(coin='ETH',wallets={'ETH':ETH}));p=core.config(s,1)['pools'][0]
  self.assertEqual(p['user'],'ETH:'+ETH+'.IdleMinerLinux');self.assertEqual(p['url'],'rx.unmineable.com:443');self.assertTrue(p['tls'])
  account={'success':True,'data':dict(network='ETH',balance_payable='0.1')}
  stats={'success':True,'data':dict(network='ETH',coin='ETH',balance='0.1',paid='0',payment_threshold='.01')}
  self.assertEqual(core.pool_snapshot(account,stats,'ETH')['balance'],.1)
  stats['data']['network']='BSC'
  with self.assertRaises(ValueError):core.pool_snapshot(account,stats,'ETH')
 def test_migration_adds_blank_eth_and_default_off(self):
  s=core.validated(dict(coin='BTC',address=BTC));self.assertEqual(s['wallets'],dict(BTC=BTC,LTC='',DOGE='',ETH=''));self.assertIs(s.get('start_mining_at_login'),False)
  with self.assertRaises(ValueError):core.validated(dict(start_mining_at_login=1))
 def test_eth_profile_uses_duplicate_lease_and_quota(self):
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(d,'ETH');b=Coordinator(d,'BTC')
   try:
    with self.assertRaises(BlockingIOError):Coordinator(d,'ETH')
    self.assertEqual(a.update('ETH',4,4,8),4);a.reserve(4);self.assertEqual(b.update('BTC',4,4,8),0)
    self.assertEqual(a.update('ETH',4,4,8),2);a.reserve(2);self.assertEqual(b.update('BTC',4,4,8),2)
   finally:a.close();b.close()

class Startup(unittest.TestCase):
 def settings(self):return core.validated(dict(coin='LTC',wallets=dict(BTC=BTC,ETH=ETH),start_mining_at_login=True))
 def test_manual_plain_login_and_disabled_parent_do_not_mine(self):
  import startup
  s=self.settings()
  for args,enabled in (([],True),(['--login-startup'],False),(['--start-mining'],True)):
   self.assertEqual(startup.startup_plan(s,'default',args,enabled),(None,()))
  s['start_mining_at_login']=False
  self.assertEqual(startup.startup_plan(s,'default',['--login-startup'],True),(None,()))
 def test_login_starts_all_valid_wallets_once_and_prefers_selected(self):
  import startup
  s=self.settings();self.assertEqual(startup.startup_plan(s,'default',['--login-startup'],True),('BTC',('ETH',)))
  s['coin']='ETH';s['address']=ETH
  self.assertEqual(startup.startup_plan(s,'default',['--login-startup'],True),('ETH',('BTC',)))
  s['wallets']['BTC']='bad';self.assertEqual(startup.startup_plan(s,'default',['--login-startup'],True),('ETH',()))
  s['wallets']['ETH']='';self.assertEqual(startup.startup_plan(s,'default',['--login-startup'],True),(None,()))
 def test_all_four_valid_wallets_start_once_with_current_currency_first(self):
  import startup
  s=core.validated(dict(coin='LTC',start_mining_at_login=True,wallets=dict(BTC=BTC,LTC='LKDyUEtTR1HXamkiEphisSiBJu6o3ZPE34',DOGE='D597kHXGdkwkryF9oGhz9Bp1ypTpD1u99Z',ETH=ETH)))
  self.assertEqual(startup.startup_plan(s,'default',['--login-startup'],True),('LTC',('BTC','DOGE','ETH')))
 def test_named_child_starts_only_itself_never_fans_out(self):
  import startup
  s=self.settings()
  self.assertEqual(startup.startup_plan(s,'ETH',['--start-mining'],False),('ETH',()))
  self.assertEqual(startup.startup_plan(s,'ETH',['--login-startup'],True),(None,()))
  self.assertEqual(startup.startup_plan(s,'DOGE',['--start-mining'],True),(None,()))
 def test_stale_preferences_save_preserves_immediate_login_changes(self):
  import startup
  with tempfile.TemporaryDirectory() as d:
   store=SettingsStore(d);old=store.load();startup.save_login_preference(store,True);stale=core.validated(old);stale['idle_threads']=8
   self.assertTrue(store.save(stale,old)['start_mining_at_login'])
   startup.save_login_preference(store,False);self.assertFalse(store.load()['start_mining_at_login'])
 def test_desktop_launchers_only_autostart_gets_argument_and_disabled_state_survives(self):
  import startup
  regular='[Desktop Entry]\nType=Application\nExec="/tmp/a b/idle-miner"\nName=Idle Miner\n'
  login=startup.login_entry(regular);self.assertIn('Exec="/tmp/a b/idle-miner" --login-startup\n',login);self.assertNotIn('--login-startup',regular)
  self.assertEqual(startup.login_entry(login),login)
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'auto.desktop';self.assertFalse(startup.autostart_enabled(p));p.write_text(login);self.assertTrue(startup.autostart_enabled(p))
   for disabled in ('Hidden=true','X-GNOME-Autostart-enabled=false'):
    old=login+disabled+'\n';p.write_text(startup.login_entry(regular,old));self.assertFalse(startup.autostart_enabled(p));self.assertIn(disabled,p.read_text())

class Installer(unittest.TestCase):
 def install(self,home):
  root=Path(__file__).resolve().parents[1];build=home/'build'
  for name in ('xmrig-build/xmrig','idle-build/idle-monitor','miner-supervisor'):
   p=build/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture')
  return subprocess.run([sys.executable,str(root/'install_files.py')],cwd=root,env={**os.environ,'HOME':str(home),'IDLE_MINER_BUILD':str(build),'PYTHONDONTWRITEBYTECODE':'1'},capture_output=True,text=True)
 def test_reinstall_updates_existing_autostart_only_and_preserves_disabled(self):
  with tempfile.TemporaryDirectory() as d:
   home=Path(d);auto=home/'.config/autostart/idle-miner.desktop'
   first=self.install(home);self.assertEqual(first.returncode,0,first.stderr);self.assertFalse(auto.exists())
   auto.parent.mkdir(parents=True);auto.write_text('[Desktop Entry]\nExec=old\nHidden=true\n')
   second=self.install(home);self.assertEqual(second.returncode,0,second.stderr)
   self.assertIn('--login-startup',auto.read_text());self.assertIn('Hidden=true',auto.read_text());self.assertNotIn('--login-startup',(home/'.local/share/applications/idle-miner.desktop').read_text())
 def test_installer_refuses_live_eth_profile(self):
  with tempfile.TemporaryDirectory() as d:
   home=Path(d);c=Coordinator(home/'.config/idle-miner','ETH')
   try:
    result=self.install(home);self.assertNotEqual(result.returncode,0);self.assertIn('Quit ALL',result.stderr);self.assertFalse((home/'.local/share/idle-miner').exists())
   finally:c.close()
if __name__=='__main__':unittest.main()
