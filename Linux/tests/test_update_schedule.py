"""Scheduled discovery only: real shared state, authenticated transport seam, no engines."""
import sys,tempfile,threading,unittest,subprocess,json
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from coordination import SettingsStore
import core,updates
class ScheduledUpdates(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.state=Path(self.temp.name);self.store=SettingsStore(self.state)
  self.release=dict(version='2.0',build=99,releaseNotesText='New release',url='https://idleminer.app/downloads/v2.0/Idle-Miner-2.0-Linux.tar.gz',sha256='a'*64,length=1,edSignature='A'*86+'==')
 def tearDown(self):self.temp.cleanup()
 def enabled(self,value=True,frequency='daily'):
  baseline=self.store.load();return self.store.save({**baseline,'automatic_update_checks':value,'update_check_frequency':frequency},baseline)
 def scheduler(self):
  self.assertTrue(hasattr(updates,'AutomaticUpdates'),'Scheduled signed discovery is missing')
  return updates.AutomaticUpdates(self.state)
 def run_at(self,scheduler,wall=1000,uptime=100,boot='one',release=None,error=None):
  with patch.object(updates,'fetch_manifest',side_effect=error,return_value=release or self.release) as fetch:
   result=scheduler.run_once(core.VERSION,core.BUILD,wall=wall,uptime=uptime,boot=boot)
   return result,fetch.call_count
 def test_default_off_creates_no_schedule_or_settings(self):
  self.assertIs(self.store.load().get('automatic_update_checks'),False,'Existing installs must migrate with checks OFF')
  self.assertEqual(self.store.load()['update_check_frequency'],'daily')
  self.assertEqual(self.run_at(self.scheduler())[1],0);self.assertEqual(list(self.state.iterdir()),[])
 def test_daily_weekly_exact_intervals_and_restart(self):
  for frequency,interval in [('daily',86400),('weekly',604800)]:
   with self.subTest(frequency=frequency):
    for path in self.state.iterdir():path.unlink()
    self.enabled(frequency=frequency);scheduler=self.scheduler()
    result,calls=self.run_at(scheduler);self.assertEqual(calls,1);self.assertTrue(result['notify'])
    self.assertEqual(self.run_at(self.scheduler(),wall=1000+interval-1,uptime=100+interval-1)[1],0)
    result,calls=self.run_at(self.scheduler(),wall=1000+interval,uptime=100+interval)
    self.assertEqual(calls,1);self.assertFalse(result['notify'],'Same release notification must survive restart')
 def test_shared_concurrent_lease_and_notification(self):
  self.enabled();scheduler=self.scheduler();entered=threading.Event();release=threading.Event();results=[]
  def fetch():entered.set();release.wait(5);return self.release
  with patch.object(updates,'fetch_manifest',side_effect=fetch) as transport:
   worker=threading.Thread(target=lambda:results.append(scheduler.run_once(core.VERSION,core.BUILD,wall=1000,uptime=100,boot='one')));worker.start()
   self.assertTrue(entered.wait(3));self.assertIsNone(self.scheduler().run_once(core.VERSION,core.BUILD,wall=1000,uptime=100,boot='one'))
   release.set();worker.join(5);self.assertEqual(transport.call_count,1);self.assertTrue(results[0]['notify'])
 def test_errors_and_signature_failure_record_attempt_silently(self):
  self.enabled()
  for error in (OSError('offline'),ValueError('Invalid manifest signature')):
   for path in self.state.glob('automatic-updates.json'):path.unlink()
   self.assertIsNone(self.run_at(self.scheduler(),error=error)[0]);self.assertEqual(self.run_at(self.scheduler(),wall=1001,uptime=101)[1],0)
   self.assertIsNone(self.scheduler().available(core.VERSION,core.BUILD))
 def test_current_release_silent_new_build_notifies_once(self):
  self.enabled();scheduler=self.scheduler()
  result,calls=self.run_at(scheduler,release=dict(self.release,version=core.VERSION,build=core.BUILD))
  self.assertIsNone(result);self.assertIsNone(scheduler.available(core.VERSION,core.BUILD))
  result,calls=self.run_at(scheduler,wall=87400,uptime=86500);self.assertTrue(result['notify'])
  self.assertEqual(scheduler.available(core.VERSION,core.BUILD),{'version':'2.0','build':99})
  result,calls=self.run_at(scheduler,wall=173800,uptime=172900,release=dict(self.release,build=100));self.assertTrue(result['notify'])
 def test_disable_during_request_suppresses_notification_and_schedule_resumes(self):
  self.enabled();scheduler=self.scheduler()
  def fetch():self.enabled(False);return self.release
  with patch.object(updates,'fetch_manifest',side_effect=fetch):self.assertIsNone(scheduler.run_once(core.VERSION,core.BUILD,wall=1000,uptime=100,boot='one'))
  self.assertEqual(self.run_at(scheduler,wall=87400,uptime=86500)[1],0)
  self.enabled();self.assertEqual(self.run_at(scheduler,wall=87400,uptime=86500)[1],1)
 def test_clock_rollback_uses_boottime_no_retry_storm(self):
  self.enabled();scheduler=self.scheduler();self.run_at(scheduler)
  self.assertEqual(self.run_at(scheduler,wall=1,uptime=200)[1],0);self.assertEqual(self.run_at(scheduler,wall=2,uptime=86500)[1],1)
  self.assertEqual(self.run_at(scheduler,wall=1,uptime=1,boot='two')[1],0)
 def test_selective_preferences_merge_preserves_wallet_login_and_stale_window(self):
  old=self.store.load();self.enabled(True,'weekly');edit=core.validated(old);edit['start_mining_at_login']=True;edit['wallets']['BTC']='1BoatSLRHtKNngkdXEeobR76b53LETtpyT';self.store.save(edit,old)
  current=self.store.load();self.assertTrue(current.get('automatic_update_checks'));self.assertEqual(current['update_check_frequency'],'weekly');self.assertTrue(current['start_mining_at_login']);self.assertTrue(current['wallets']['BTC'])
 def test_invalid_frequency_rejected(self):
  with self.assertRaises(ValueError):core.validated({'update_check_frequency':'Hourly'})

 def test_signed_service_rollback_cannot_repeat_prior_notifications(self):
  self.enabled();scheduler=self.scheduler();self.run_at(scheduler)
  self.run_at(scheduler,wall=87400,uptime=86500,release=dict(self.release,build=100))
  result,calls=self.run_at(scheduler,wall=173800,uptime=172900)
  self.assertFalse(result['notify'],'An older signed service response must not notify again')
  self.assertEqual(scheduler.available(core.VERSION,core.BUILD),{'version':'2.0','build':100})

 def test_frequency_change_uses_existing_attempt_and_settings_remain_disabled(self):
  self.enabled(frequency='weekly');scheduler=self.scheduler();self.run_at(scheduler)
  self.enabled(frequency='daily');self.assertEqual(self.run_at(scheduler,wall=87400,uptime=86500)[1],1)
  self.enabled(False);self.assertEqual(self.run_at(scheduler,wall=999999,uptime=999999)[1],0)
 def test_distinct_processes_share_attempt_and_restart_notification_identity(self):
  self.enabled()
  source="""from pathlib import Path
import json,sys,time
import updates,core
state=Path(sys.argv[1])
def fetch():
 with open(state/'requests','a') as f:f.write('request'+chr(10))
 time.sleep(.15)
 return json.loads(sys.argv[2])
updates.fetch_manifest=fetch
print(json.dumps(updates.AutomaticUpdates(state).run_once(core.VERSION,core.BUILD,wall=1000,uptime=100,boot='one')))
"""
  children=[subprocess.Popen([sys.executable,'-c',source,str(self.state),json.dumps(self.release)],cwd=Path(__file__).resolve().parents[1],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) for _ in range(2)]
  results=[]
  completed=[(child,child.communicate(timeout=5)) for child in children]
  for child,(output,error) in completed:
   self.assertEqual(child.returncode,0,error);results.append(json.loads(output))
  self.assertEqual((self.state/'requests').read_text().splitlines(),['request']);self.assertEqual(sum(bool(r and r['notify']) for r in results),1)
  self.assertEqual(self.run_at(self.scheduler(),wall=1001,uptime=101)[1],0)
