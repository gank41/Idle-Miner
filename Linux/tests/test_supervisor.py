"""Actual supervisor crash/reap lifecycle, without wallets, pool access or RandomX RAM."""
import unittest,sys,tempfile,subprocess,os,time,json,fcntl
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from coordination import Coordinator
SUPERVISOR=Path(os.environ.get('IDLE_MINER_SUPERVISOR',str(Path.home()/'.local/share/idle-miner/miner-supervisor')))
@unittest.skipUnless(sys.platform=='linux' and SUPERVISOR.exists(),'Linux compiled supervisor required')
class Supervisor(unittest.TestCase):
 def test_crashed_controller_keeps_actual_engine_lease_until_reaped(self):
  with tempfile.TemporaryDirectory() as d:
   source=Path(d)/'owner.py'
   source.write_text("from pathlib import Path\nimport sys,subprocess,os,time,json\nfrom coordination import Coordinator\nc=Coordinator(Path(sys.argv[1]),'default');c.update('LTC',4,4,8)\np=subprocess.Popen([sys.argv[2],str(os.getpid()),'--lease='+str(c.engine_lock),sys.executable,'-u','-c',\"import signal,time,os;signal.signal(signal.SIGINT,signal.SIG_IGN);print('ENGINE '+str(os.getpid()),flush=True);time.sleep(60)\"])\nprint('OWNER '+str(p.pid),flush=True)\ntime.sleep(60)\n")
   env={**os.environ,'PYTHONPATH':str(Path(__file__).resolve().parents[1])+':'+os.environ.get('PYTHONPATH','')}
   child=subprocess.Popen([sys.executable,str(source),d,str(SUPERVISOR)],env=env,stdout=subprocess.PIPE,text=True)
   try:
    lines=[child.stdout.readline().strip(),child.stdout.readline().strip()]
    self.assertTrue(any(x.startswith('ENGINE ') for x in lines),lines)
    peer=Coordinator(Path(d),'BTC')
    try:
     child.kill();child.wait(timeout=5)
     self.assertEqual(peer.update('BTC',4,4,8),0)
     with self.assertRaises(BlockingIOError):Coordinator(Path(d),'default')
     time.sleep(.4);self.assertEqual(peer.update('BTC',4,4,8),0)
     deadline=time.monotonic()+6
     while time.monotonic()<deadline and peer.update('BTC',4,4,8)==0:time.sleep(.05)
     self.assertEqual(peer.update('BTC',4,4,8),4)
     self.assertGreater(time.monotonic(),deadline-6+.4)
    finally:peer.close()
   finally:
    if child.poll() is None:child.kill();child.wait()
    child.stdout.close()
