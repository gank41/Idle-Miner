import os,sys,subprocess,time,signal
helper=sys.argv[1]
def alive(pid):
 try: os.kill(pid,0); return True
 except ProcessLookupError:return False
def child_of(pid):
 for _ in range(30):
  r=subprocess.run(['/usr/bin/pgrep','-P',str(pid)],capture_output=True,text=True)
  if r.returncode==0:return int(r.stdout.split()[0])
  time.sleep(.1)
 raise AssertionError('engine child did not start')
# A stale/app-already-dead owner must be rejected before any engine launches.
r=subprocess.run([helper,'1','/bin/sleep','30'],capture_output=True,timeout=5)
assert r.returncode==64,('stale owner not rejected',r.returncode)
p=subprocess.Popen([helper,str(os.getpid()),'/bin/sleep','30'])
try:
 engine=child_of(p.pid); p.send_signal(signal.SIGINT); p.wait(timeout=6)
 assert not alive(engine),'Stop left engine alive'
finally:
 if p.poll() is None:p.terminate();p.wait(timeout=6)
launcher='import subprocess,os,sys,time; p=subprocess.Popen([sys.argv[1],str(os.getpid()),"/bin/sleep","30"]); print(p.pid,flush=True); time.sleep(30)'
owner=subprocess.Popen([sys.executable,'-c',launcher,helper],stdout=subprocess.PIPE,text=True)
supervisor=int(owner.stdout.readline()); engine=child_of(supervisor)
owner.kill();owner.wait(timeout=3)
for _ in range(60):
 if not alive(engine):break
 time.sleep(.1)
assert not alive(engine),'App crash left engine alive'
print('PASS: stale parent rejected; Stop and app-crash cleanup terminate owned engine')
