"""Two real processes and XMRig datasets, only offline benchmarking; no real settings copied."""
import os,sys,tempfile,subprocess,time,json,selectors
from pathlib import Path
root=Path(__file__).resolve().parent
state=Path(tempfile.mkdtemp(prefix='idle-real-multi-'));env={**os.environ,'IDLE_MINER_STATE':str(state),'QT_QPA_PLATFORM':'offscreen'}
workers=[];selector=selectors.DefaultSelector();latest={};records=[]
def launch(profile):
 p=subprocess.Popen([sys.executable,str(root/'multi_engine_worker.py'),profile],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,bufsize=1)
 workers.append(p);selector.register(p.stdout,selectors.EVENT_READ,profile);return p
def wait_for(predicate,seconds=100):
 deadline=time.monotonic()+seconds
 while time.monotonic()<deadline:
  for key,_ in selector.select(.25):
   line=key.fileobj.readline()
   if not line:selector.unregister(key.fileobj);continue
   try:r=json.loads(line)
   except ValueError:continue
   records.append(r);latest[r['profile']]=r;print(line.rstrip(),flush=True)
   assert not r['fatal'],r
  if predicate():return
 raise AssertionError('Timed out waiting for actual engine READY quota')
try:
 first=launch('default');wait_for(lambda:latest.get('default',{}).get('ready') and latest['default']['threads']==2)
 second=launch('BTC');wait_for(lambda:all(latest.get(p,{}).get('ready') and latest[p]['threads']==1 for p in ('default','BTC')))
 assert sum(r['reserved'] for r in latest.values())<=2
 print('PASS: two separate real engines report READY 1/1, shared two-thread cap',flush=True)
 (state/'default.stop').touch();wait_for(lambda:latest.get('default',{}).get('pid')==0 and latest.get('BTC',{}).get('ready') and latest['BTC']['threads']==2)
 print('PASS: surviving engine reports READY 2/2 only after stopped peer reap releases capacity',flush=True)
 third=launch('DOGE');wait_for(lambda:all(latest.get(p,{}).get('ready') and latest[p]['threads']==1 for p in ('BTC','DOGE')))
 crashed_engine=latest['DOGE']['pid'];third.kill();third.wait(timeout=5)
 wait_for(lambda:latest.get('BTC',{}).get('ready') and latest['BTC']['threads']==2)
 assert not (state/'DOGE.peer.json').exists()
 print('PASS: actual peer controller crash releases quota after its owned real engine is reaped',flush=True)
 (state/'BTC.stop').touch()
 for p in workers:p.wait(timeout=12)
 logs=list(state.rglob('*.log'));text='\n'.join(f.read_text() for f in logs)
 assert 'READY threads 1/1' in text and 'READY threads 2/2' in text
 assert 'rx.unmineable.com' not in text
 print('PASS: profile configs/logs isolated; offline real engine evidence retained in '+str(state),flush=True)
finally:
 for p in workers:
  if p.poll() is None:p.terminate()
 for p in workers:
  try:p.wait(timeout=8)
  except subprocess.TimeoutExpired:p.kill();p.wait()
  error=p.stderr.read()
  if error:print(error[-1500:],file=sys.stderr)
  p.stdout.close();p.stderr.close()
