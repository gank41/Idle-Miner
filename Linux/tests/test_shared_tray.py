import json, os, subprocess, sys, tempfile, time, unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from coordination import Coordinator
from shared_tray import SharedTray,write_json,profile_currency,focus_matches

class SharedTrayTests(unittest.TestCase):
 def test_one_owner_and_takeover_without_removing_stable_lock(self):
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(d,'BTC');b=Coordinator(d,'LTC');x=SharedTray(d,a);y=SharedTray(d,b)
   try:
    self.assertTrue(x.elect());self.assertFalse(y.elect());inode=x.lease_path.stat().st_ino
    x.close();self.assertTrue(y.elect());self.assertEqual(inode,y.lease_path.stat().st_ino)
   finally:x.close();y.close();a.close();b.close()
 def test_freshness_identity_and_private_permissions(self):
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(d,'BTC');x=SharedTray(d,a)
   try:
    a.update('BTC',0,4,8);x.publish('BTC',{'color':'green','state':'Mining','rate':'10 H/s'})
    self.assertEqual(x.snapshots()['BTC']['color'],'green')
    self.assertEqual(x.directory.stat().st_mode&0o777,0o700)
    self.assertEqual(x.path.stat().st_mode&0o777,0o600)
    data=json.loads(x.path.read_text());data['time']=time.time()-30;x.path.write_text(json.dumps(data))
    self.assertEqual(x.snapshots()['BTC']['color'],'gray')
    data['time']=time.time();data['pid']+=1;x.path.write_text(json.dumps(data));self.assertEqual(x.snapshots(),{})
   finally:x.close();a.close()
 def test_commands_match_nonce_pid_currency_and_expire(self):
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(d,'BTC');x=SharedTray(d,a)
   try:
    a.update('BTC',0,4,8);x.publish('BTC',{'color':'gray','state':'Stopped'});target=x.snapshots()['BTC']
    self.assertTrue(x.send(target,'show_stats'));self.assertEqual(x.take_commands('BTC'),['show_stats']);self.assertEqual(x.take_commands('BTC'),[])
    for field,value in [('nonce','0'*32),('pid',os.getpid()+1),('coin','LTC')]:
     invalid={**target,field:value};self.assertTrue(x.send(invalid,'start'));self.assertEqual(x.take_commands('BTC'),[])
    self.assertFalse(x.send(target,'run shell'));self.assertFalse(x.send(target,'boost:17'))
    x.send(target,'stop');path=next(x.directory.glob('command-*.json'));data=json.loads(path.read_text());data['time']-=60;path.write_text(json.dumps(data));self.assertEqual(x.take_commands('BTC'),[])
   finally:x.close();a.close()
 def test_commands_follow_created_time_instead_of_uuid_filename(self):
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(d,'BTC');x=SharedTray(d,a)
   try:
    a.update('BTC',0,4,8);x.publish('BTC',{'color':'gray','state':'Stopped'});target=x.snapshots()['BTC'];created=time.time()-2
    for filename,action,timestamp in [('f'*32,'start',created),('0'*32,'stop',created+1)]:
     write_json(x.directory/('command-'+filename+'.json'),dict(schema=1,profile='BTC',pid=os.getpid(),nonce=x.nonce,coin='BTC',action=action,time=timestamp))
    self.assertEqual(x.take_commands('BTC'),['start','stop'])
   finally:x.close();a.close()
 def test_stop_and_quit_execute_last_when_created_times_tie(self):
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(d,'BTC');x=SharedTray(d,a)
   try:
    a.update('BTC',0,4,8);created=time.time()-1
    for filename,action in [('0'*32,'quit'),('1'*32,'stop'),('2'*32,'start'),('3'*32,'boost:15')]:
     write_json(x.directory/('command-'+filename+'.json'),dict(schema=1,profile='BTC',pid=os.getpid(),nonce=x.nonce,coin='BTC',action=action,time=created))
    self.assertEqual(x.take_commands('BTC'),['start','boost:15','stop','quit'])
   finally:x.close();a.close()
 def test_profile_open_never_matches_a_switched_currency(self):
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(d,'BTC');x=SharedTray(d,a)
   try:
    a.update('ETH',0,4,8)
    self.assertEqual(profile_currency(d,'BTC'),'ETH')
    self.assertFalse(focus_matches(d,'BTC','BTC'));self.assertTrue(focus_matches(d,'BTC','ETH'))
    self.assertIsNone(profile_currency(d,'LTC'));self.assertFalse(focus_matches(d,'LTC','LTC'))
   finally:x.close();a.close()
 def test_focus_request_is_bound_to_current_currency_after_switch(self):
  with tempfile.TemporaryDirectory() as d:
   a=Coordinator(d,'BTC')
   try:
    a.request_focus('BTC');self.assertFalse(a.take_focus('ETH'))
    a.request_focus('ETH');self.assertTrue(a.take_focus('ETH'))
    self.assertFalse(a.take_focus('ETH'))
   finally:a.close()
 def test_owner_crash_releases_tray_and_stale_green_not_replayed(self):
  with tempfile.TemporaryDirectory() as d:
   source="from coordination import Coordinator;from shared_tray import SharedTray,write_json,profile_currency,focus_matches;import sys,time;c=Coordinator(sys.argv[1],'BTC');c.update('BTC',0,4,8);s=SharedTray(sys.argv[1],c);s.publish('BTC',{'color':'green','state':'Mining'});print(s.elect(),flush=True);time.sleep(60)"
   p=subprocess.Popen([sys.executable,'-c',source,d],cwd=Path(__file__).resolve().parents[1],stdout=subprocess.PIPE,text=True)
   try:
    self.assertEqual(p.stdout.readline().strip(),'True');a=Coordinator(d,'LTC');x=SharedTray(d,a)
    try:
     self.assertFalse(x.elect());p.kill();p.wait(timeout=5);self.assertTrue(x.elect());self.assertNotIn('BTC',x.snapshots())
    finally:x.close();a.close()
   finally:
    if p.poll() is None:p.kill();p.wait()
    p.stdout.close()
if __name__=='__main__':unittest.main()
