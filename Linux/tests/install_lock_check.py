"""Verify installed files/settings stay byte-identical when a named profile is live."""
import os,sys,subprocess,hashlib,time
from pathlib import Path
root=Path(__file__).resolve().parents[1];installed=Path.home()/'.local/share/idle-miner';state=Path.home()/'.config/idle-miner'
files=[p for p in installed.iterdir() if p.is_file()]
if (state/'settings.json').exists():files.append(state/'settings.json')
def digest():return {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
before=digest()
source="from pathlib import Path;from coordination import Coordinator;import time;c=Coordinator(Path.home()/'.config/idle-miner','BTC');print('LOCKED',flush=True);time.sleep(60)"
child=subprocess.Popen([sys.executable,'-c',source],cwd=root,stdout=subprocess.PIPE,text=True)
try:
 assert child.stdout.readline().strip()=='LOCKED'
 result=subprocess.run([sys.executable,'install_files.py'],cwd=root,capture_output=True,text=True)
 assert result.returncode!=0 and 'Quit ALL' in result.stderr,result
 assert digest()==before
 print('PASS: installer refuses live named currency profile; all installed files/settings byte-identical',flush=True)
finally:
 child.kill();child.wait(timeout=5);child.stdout.close()
