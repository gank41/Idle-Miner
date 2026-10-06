import unittest,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from core import *
class Tests(unittest.TestCase):
 def test_wallet(self):
  a='1BoatSLRHtKNngkdXEeobR76b53LETtpyT'
  self.assertTrue(valid_wallet(a,'BTC'))
  for bad in (a[:-1]+'A',a+' ',a+'.worker',a+'\n',a.lower()): self.assertFalse(valid_wallet(bad,'BTC'))
  self.assertFalse(valid_wallet(a,'LTC'))
 def test_safety_beats_boost(self):
  s=DEFAULTS.copy(); e=Environment(idle=True,idle_known=True,cores=16)
  self.assertEqual(threads(s,e),4)
  for field in ('hot','memory_low'):
   setattr(e,field,True); self.assertEqual(threads(s,e,True),0); setattr(e,field,False)
  e.on_ac=False; self.assertEqual(threads(s,e,True),0)
 def test_active_unknown_and_headroom(self):
  s=DEFAULTS.copy(); e=Environment(cores=4)
  self.assertEqual(threads(s,e),1); self.assertEqual(threads(s,e,True),2)
  s['pause_active']=True; self.assertEqual(threads(s,e),0)
  e.idle=e.idle_known=True; self.assertEqual(threads(s,e),2)
  self.assertEqual(threads(s,e,ceiling=1),1)
 def test_health_and_donation(self):
  w=Work(); w.engine_started(); t=w.started
  self.assertEqual(w.health(True,True,t=t)[0],'gray')
  w.consume('new job from rx.unmineable.com',t)
  w.consume('speed 10s/60s/15m 512.3 n/a n/a H/s',t+1)
  self.assertEqual(w.health(True,True,t=t+2)[0],'green')
  self.assertEqual(w.health(True,True,t=t+32)[0],'red')
  w.consume('donate started'); w.consume('accepted (1/0)'); self.assertEqual(w.accepted,0)
  w.consume('donate finished'); w.consume('accepted (1/0)'); self.assertEqual(w.accepted,1)
  w.consume('read error'); self.assertEqual(w.health(True,True,t=t+3)[0],'red')
  self.assertEqual(w.health(False,False)[0],'gray')
 def test_zero_and_unavailable_rates(self):
  w=Work(); w.engine_started();t=w.started;w.consume('new job from rx.unmineable.com',t)
  w.consume('speed 10s/60s/15m 512.3 n/a n/a H/s',t)
  w.consume('speed 10s/60s/15m n/a n/a n/a H/s',t+5)
  self.assertIsNone(w.rate)
  w.consume('speed 10s/60s/15m 0 0 0 H/s',t+31)
  self.assertEqual(w.health(True,True,t=t+31)[0],'red')
 def test_offline_never_earns(self):
  w=Work(); w.engine_started(True);w.consume('accepted (1/0)');self.assertEqual(w.accepted,0)
  c=config(DEFAULTS,1,True); self.assertEqual(c['pools'],[]);self.assertFalse(c['http']['enabled']); self.assertEqual(c['benchmark']['size'],'1M'); self.assertTrue(c['cpu']['yield'])
  with self.assertRaises(ValueError): config(DEFAULTS,1)
 def test_account_validation(self):
  a={'success':True,'data':{'network':'LTC','balance_payable':'0.1','auto':True}}
  s={'success':True,'data':{'network':'LTC','coin':'LTC','balance':'0.2','paid':'0','payment_threshold':'1'}}
  self.assertEqual(pool_snapshot(a,s,'LTC')['balance'],.2)
  with self.assertRaises(ValueError): pool_snapshot(a,s,'BTC')
  s['data']['balance']='NaN'
  with self.assertRaises(ValueError): pool_snapshot(a,s,'LTC')
if __name__=='__main__': unittest.main()
