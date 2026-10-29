"""Private update handoff: exact pre-shutdown state, success-only single use."""
import copy,json,os,sys,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import updates

class ResumeTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.base=Path(self.temp.name)
  self.root=self.base/'custom install';self.root.mkdir();(self.root/'core.py').write_text("VERSION = '1.9'\nBUILD = 12\n")
  self.state=self.base/'state';self.state.mkdir(mode=0o700)
  self.rows=[dict(profile=p,coin=c,pid=os.getpid(),nonce=str(i)*32) for i,(p,c) in enumerate([('default','ETH'),('BTC','BTC'),('LTC','LTC'),('DOGE','DOGE')],1)]
  self.wallet=self.state/'settings.json';self.wallet.write_bytes(b'{"wallets":"untouched", "pause_active": true}\n')
 def begin(self):return updates.begin_resume(self.state,self.root,'1.9',12,'1.9.1',13,self.rows,'default')
 def acknowledge(self,token):
  for row,enabled in zip(self.rows,[True,False,True,True]):
   self.assertTrue(updates.acknowledge_resume(self.state,self.root,token,row['profile'],row['pid'],row['nonce'],row['coin'],enabled))
 def install(self,token):
  plan=updates.finalize_resume(self.state,self.root,token,timeout=0)
  (self.root/'core.py').write_text("VERSION = '1.9.1'\nBUILD = 13\n")
  return updates.publish_resume(self.state,self.root,plan)
 def consume(self,token,profile='default',**kwargs):return updates.consume_resume(self.state,self.root,token,profile,'1.9.1',13,**kwargs)
 def test_mixed_enabled_stopped_and_switched_profiles_restore_once(self):
  original=self.wallet.read_bytes();token=self.begin();self.acknowledge(token);self.install(token)
  main=self.consume(token);self.assertEqual(main['coin'],'ETH');self.assertTrue(main['enabled']);self.assertEqual({r['profile'] for r in main['peers']},{'BTC','LTC','DOGE'})
  self.assertIsNone(self.consume(token))
  for row,enabled in zip(self.rows[1:],[False,True,True]):
   item=self.consume(token,row['profile']);self.assertEqual(item['enabled'],enabled);self.assertEqual(item['coin'],row['coin']);self.assertEqual(item['peers'],[])
  self.assertEqual(self.wallet.read_bytes(),original)
 def test_snapshot_enabled_is_not_used_and_manual_stop_before_ack_wins(self):
  token=self.begin();row=self.rows[0]
  self.assertTrue(updates.acknowledge_resume(self.state,self.root,token,row['profile'],row['pid'],row['nonce'],'DOGE',False))
  self.assertEqual(updates.read_private(updates.resume_directory(self.state,token)/(row['profile']+'.json'))['coin'],'DOGE')
  self.assertFalse(updates.read_private(updates.resume_directory(self.state,token)/(row['profile']+'.json'))['enabled'])
 def test_ack_is_atomic_and_first_capture_cannot_be_overwritten(self):
  token=self.begin();row=self.rows[0];real_link=os.link;observed=[]
  def inspect(source,target,**kwargs):
   self.assertFalse(Path(target).exists());observed.append(updates.read_private(source));return real_link(source,target,**kwargs)
  with patch('updates.os.link',side_effect=inspect):
   self.assertTrue(updates.acknowledge_resume(self.state,self.root,token,row['profile'],row['pid'],row['nonce'],'ETH',False))
  self.assertEqual(len(observed),1);self.assertIs(observed[0]['enabled'],False)
  self.assertFalse(updates.acknowledge_resume(self.state,self.root,token,row['profile'],row['pid'],row['nonce'],'BTC',True))
  self.assertIs(updates.read_private(updates.resume_directory(self.state,token)/'default.json')['enabled'],False)
 def test_parallel_receipt_consumers_cannot_resume_same_profile_twice(self):
  import subprocess
  token=self.begin();self.acknowledge(token);self.install(token)
  source='import sys;from pathlib import Path;import updates;print(bool(updates.consume_resume(Path(sys.argv[1]),Path(sys.argv[2]),sys.argv[3],"default","1.9.1",13)),flush=True)'
  env={**os.environ,'PYTHONPATH':str(Path(updates.__file__).parent)}
  children=[subprocess.Popen([sys.executable,'-c',source,str(self.state),str(self.root),token],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=env) for _ in range(2)]
  outcomes=[]
  for child in children:
   out,err=child.communicate(timeout=8);self.assertEqual(child.returncode,0,err);outcomes.append(out.strip())
  self.assertEqual(sorted(outcomes),['False','True'])
 def test_missing_ack_or_wrong_nonce_never_finalizes(self):
  token=self.begin();row=self.rows[0]
  self.assertFalse(updates.acknowledge_resume(self.state,self.root,token,row['profile'],row['pid'],'f'*32,'ETH',True))
  with self.assertRaises(ValueError):updates.finalize_resume(self.state,self.root,token,timeout=0)
 def test_ack_rejects_wrong_root_source_pid_expired_and_boolean_pid(self):
  for field,value in [('root',str(self.base)),('sourceBuild',999),('created',time.time()-1000),('created',time.time()+1000),('schema',True),('pid',True)]:
   token=self.begin();path=updates.resume_directory(self.state,token)/'request.json';data=updates.read_private(path)
   if field=='pid':data['targets'][0][field]=value
   else:data[field]=value
   updates.write_private(path,data);row=self.rows[0]
   self.assertFalse(updates.acknowledge_resume(self.state,self.root,token,row['profile'],row['pid'],row['nonce'],'ETH',True),field)
 def test_receipt_rejects_wrong_location_build_expiry_and_no_marker(self):
  token=self.begin();self.acknowledge(token);self.install(token)
  self.assertIsNone(updates.consume_resume(self.state,self.base,None,'default','1.9.1',13))
  self.assertIsNone(updates.consume_resume(self.state,self.base,token,'default','1.9.1',13))
  self.assertIsNone(updates.consume_resume(self.state,self.root,token,'default','1.9.1',14))
  receipt=updates.receipt_path(self.state,token);data=updates.read_private(receipt);data['created']=time.time()-1000;updates.write_private(receipt,data)
  self.assertIsNone(self.consume(token))
 def test_receipt_rejects_symlink_public_oversized_and_malformed(self):
  for kind in ('symlink','public','oversized','malformed'):
   (self.root/'core.py').write_text("VERSION = '1.9'\nBUILD = 12\n")
   token=self.begin();self.acknowledge(token);self.install(token);path=updates.receipt_path(self.state,token)
   if kind=='symlink':target=path.with_suffix('.copy');path.rename(target);path.symlink_to(target)
   elif kind=='public':path.chmod(0o644)
   elif kind=='oversized':path.write_text(' '*65537)
   else:path.write_text('{bad')
   self.assertIsNone(self.consume(token),kind)
 def test_publish_only_matches_newer_installed_target(self):
  token=self.begin();self.acknowledge(token);plan=updates.finalize_resume(self.state,self.root,token,timeout=0)
  with self.assertRaises(ValueError):updates.publish_resume(self.state,self.root,plan)
  self.assertIsNone(self.consume(token))
 def test_explicit_stop_precedes_update_capture_on_same_command_timestamp(self):
  from coordination import Coordinator
  from shared_tray import SharedTray,write_json
  coordinator=Coordinator(self.state,'BTC');tray=SharedTray(self.state,coordinator);created=time.time()-1
  try:
   for filename,action in [('0'*32,'quit-update:'+'1'*32),('f'*32,'stop')]:
    write_json(tray.directory/('command-'+filename+'.json'),dict(schema=1,profile='BTC',pid=os.getpid(),nonce=tray.nonce,coin='BTC',action=action,time=created))
   self.assertEqual(tray.take_commands('BTC'),['stop','quit-update:'+'1'*32])
  finally:tray.close();coordinator.close()
 def test_update_shutdown_queues_only_acknowledging_quit_action(self):
  token=self.begin();events=[]
  class Tray:
   def send(self,row,action):events.append((row['profile'],action));return True
  updates.request_shutdown(Tray(),self.rows,token)
  self.assertEqual(events,[(row['profile'],'quit-update:'+token) for row in self.rows])

class HelperResumeTests(unittest.TestCase):
 setUp=ResumeTests.setUp
 begin=ResumeTests.begin
 acknowledge=ResumeTests.acknowledge
 install=ResumeTests.install
 consume=ResumeTests.consume
 def test_detached_helper_creates_receipt_only_after_successful_replacement(self):
  import shutil,subprocess
  token=self.begin();self.acknowledge(token)
  workspace=self.base/'workspace';workspace.mkdir();helper=workspace/'helper.py';shutil.copy2(updates.__file__,helper)
  stage=self.base/'stage';stage.mkdir()
  for name in updates.REQUIRED_FILES:(stage/name).write_text('fixture')
  for name in updates.EXECUTABLES:(stage/name).chmod(0o755)
  (stage/'core.py').write_text("VERSION = '1.9.1'\nBUILD = 13\n")
  marker=self.base/'relaunch.json'
  (stage/'app.py').write_text('import sys,json;from pathlib import Path;Path('+repr(str(marker))+').write_text(json.dumps(sys.argv))')
  result=subprocess.run([sys.executable,str(helper),'--install-prepared',str(stage),str(self.root),str(self.state),str(workspace),token],capture_output=True,text=True,timeout=10)
  self.assertEqual(result.returncode,0,result.stderr);deadline=time.monotonic()+5
  while not marker.exists() and time.monotonic()<deadline:time.sleep(.02)
  args=json.loads(marker.read_text());self.assertIn('--resume-update='+token,args);self.assertIn('--profile=default',args)
  self.assertEqual(self.consume(token)['coin'],'ETH');self.assertFalse(workspace.exists())
  self.assertEqual(self.wallet.read_bytes(),b'{"wallets":"untouched", "pause_active": true}\n')
 def test_failed_install_or_target_mismatch_discards_resume(self):
  for failure in ('replace','target'):
   token=self.begin();self.acknowledge(token);workspace=self.base/('workspace-'+failure);workspace.mkdir()
   with patch('updates.installed_version',return_value=('1.9.1',13) if failure=='replace' else ('1.9.2',14)),patch('updates.replace_install',side_effect=OSError('simulated failed replacement')),patch('updates.subprocess.Popen') as launch:
    updates.helper_main(self.base/'stage',self.root,self.state,workspace,token)
   args=launch.call_args.args[0];self.assertFalse(any(a.startswith('--resume-update=') for a in args));self.assertFalse(updates.receipt_path(self.state,token).exists());self.assertFalse(workspace.exists())
 def test_downgrade_transaction_and_stale_receipt_cannot_restore(self):
  for version,build in [('1.8',999),('1.9',12)]:
   with self.assertRaises(ValueError):updates.begin_resume(self.state,self.root,'1.9',12,version,build,self.rows,'default')
  token=self.begin();self.acknowledge(token);self.install(token)
  (self.root/'core.py').write_text("VERSION = '1.9.2'\nBUILD = 14\n")
  self.assertIsNone(self.consume(token))

if __name__=='__main__':unittest.main()
