"""One tray lease per OS user; private, bounded snapshots and fixed menu commands.

The stable lease inode is never removed. This does not participate in engine or
quota ownership. Legacy profiles without this protocol keep their own UI.
"""
import fcntl, json, math, os, re, stat, time, uuid
from pathlib import Path
from core import COINS, DURATIONS

PROFILES=('default',*COINS)
ACTIONS=frozenset(('show_stats','show_log','start','stop','end_boost','settings','pool','refresh','quit',*(f'boost:{m}' for m in DURATIONS)))
FRESH_SECONDS=6
MAX_BYTES=16384

def private_directory(path):
 path=Path(path);path.mkdir(parents=True,exist_ok=True,mode=0o700)
 info=path.lstat()
 if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid():raise ValueError('Unsafe tray state directory')
 path.chmod(0o700);return path

def read_json(path):
 fd=os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0))
 with os.fdopen(fd,'rb') as stream:
  info=os.fstat(stream.fileno())
  if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode&0o077:raise ValueError('Unsafe tray state file')
  raw=stream.read(MAX_BYTES+1)
  if len(raw)>MAX_BYTES:raise ValueError('Tray state too large')
  value=json.loads(raw)
  if not isinstance(value,dict):raise ValueError('Invalid tray state')
  return value

def write_json(path,data):
 raw=json.dumps(data,ensure_ascii=True).encode('ascii')
 if len(raw)>MAX_BYTES:raise ValueError('Tray state too large')
 temp=path.with_name('.'+path.name+'.'+uuid.uuid4().hex+'.tmp')
 fd=os.open(temp,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 try:
  with os.fdopen(fd,'wb') as stream:stream.write(raw)
  temp.replace(path)
 finally:temp.unlink(missing_ok=True)

def held(path):
 try:
  fd=os.open(path,os.O_RDWR|getattr(os,'O_NOFOLLOW',0))
  with os.fdopen(fd,'a') as lock:
   if os.fstat(lock.fileno()).st_uid!=os.getuid():return False
   try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
   except BlockingIOError:return True
  return False
 except OSError:return False

def fresh(value,maximum=FRESH_SECONDS):
 return type(value) in (int,float) and math.isfinite(value) and 0<=time.time()-value<=maximum

def profile_currency(state,profile):
 if profile not in PROFILES:return None
 state=Path(state)
 try:
  peer=read_json(state/(profile+'.peer.json'))
  if peer.get('profile')!=profile or type(peer.get('pid')) is not int or peer['pid']<=0 or peer.get('coin') not in COINS:return None
  if not held(state/('app.lock' if profile=='default' else profile+'.lock')):return None
  os.kill(peer['pid'],0);return peer['coin']
 except (OSError,ValueError,TypeError):return None

def focus_matches(state,profile,coin):
 return coin in COINS and profile_currency(state,profile)==coin

class SharedTray:
 def __init__(self,state,coordinator):
  self.state=Path(state);self.directory=private_directory(self.state/'shared-tray-v1');self.coordinator=coordinator
  self.profile=coordinator.profile;self.nonce=uuid.uuid4().hex;self.path=self.directory/(self.profile+'.summary.json')
  self.lease_path=self.directory/'owner.lock';fd=os.open(self.lease_path,os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0),0o600)
  if os.fstat(fd).st_uid!=os.getuid():os.close(fd);raise ValueError('Unsafe tray lease')
  os.fchmod(fd,0o600);self.lease=os.fdopen(fd,'a');self.owner=False;self.closed=False
 def elect(self):
  if self.closed:return False
  if not self.owner:
   try:fcntl.flock(self.lease,fcntl.LOCK_EX|fcntl.LOCK_NB);self.owner=True
   except BlockingIOError:return False
  write_json(self.directory/'owner.json',dict(pid=os.getpid(),profile=self.profile,nonce=self.nonce,time=time.time()))
  return True
 def owner_available(self):
  if self.owner:return True
  try:
   data=read_json(self.directory/'owner.json')
   return data.get('profile') in PROFILES and type(data.get('pid')) is int and fresh(data.get('time')) and held(self.lease_path)
  except (OSError,ValueError,TypeError):return False
 def publish(self,coin,summary):
  if self.closed or coin not in COINS:return
  # Copy only display fields. Never serialize settings, wallet addresses or logs.
  data=dict(schema=1,profile=self.profile,pid=os.getpid(),nonce=self.nonce,coin=coin,order=self.coordinator.data['order'],time=time.time())
  data['color']=summary.get('color') if summary.get('color') in ('gray','red','green') else 'gray'
  for key in ('state','health','rate','shares','timing','money'):
   value=summary.get(key,'');data[key]=value[:1800] if isinstance(value,str) else ''
  write_json(self.path,data)
 def snapshots(self,by_profile=False):
  result={}
  for profile in PROFILES:
   try:
    data=read_json(self.directory/(profile+'.summary.json'))
    peer=read_json(self.state/(profile+'.peer.json'))
    if data.get('schema')!=1 or data.get('profile')!=profile or data.get('coin') not in COINS:continue
    if type(data.get('pid')) is not int or data['pid']<=0 or not re.fullmatch('[a-f0-9]{32}',str(data.get('nonce',''))):continue
    if peer.get('profile')!=profile or peer.get('pid')!=data['pid'] or peer.get('coin')!=data['coin'] or peer.get('order')!=data.get('order'):continue
    if not held(self.state/('app.lock' if profile=='default' else profile+'.lock')):continue
    try:os.kill(data['pid'],0)
    except OSError:continue
    if data.get('color') not in ('gray','red','green'):continue
    if any(not isinstance(data.get(k),str) or len(data[k])>1800 for k in ('state','health','rate','shares','timing','money')):continue
    data['fresh']=fresh(data.get('time'))
    if not data['fresh']:data.update(color='gray',state='Status unavailable · waiting for this currency',health='Last report is stale.',rate='Awaiting a fresh sample',shares='',timing='',money='')
    key=profile if by_profile else data['coin'];previous=result.get(key)
    # Prefer a fresh working profile over a stopped duplicate currency window.
    rank=lambda row:(row['fresh'],row['color']=='green',row['color']=='red',row['order'])
    if previous is None or rank(data)>rank(previous):result[key]=data
   except (OSError,ValueError,TypeError,KeyError):continue
  return result
 def send(self,target,action):
  if action not in ACTIONS or target.get('profile') not in PROFILES or target.get('coin') not in COINS:return False
  if type(target.get('pid')) is not int or not re.fullmatch('[a-f0-9]{32}',str(target.get('nonce',''))):return False
  self.prune()
  if len(list(self.directory.glob('command-*.json')))>=32:return False
  command=dict(schema=1,profile=target['profile'],pid=target['pid'],nonce=target['nonce'],coin=target['coin'],action=action,time=time.time())
  write_json(self.directory/('command-'+uuid.uuid4().hex+'.json'),command);return True
 def prune(self):
  for path in list(self.directory.glob('command-*.json'))[:128]:
   try:
    if not fresh(read_json(path).get('time'),10):path.unlink(missing_ok=True)
   except (OSError,ValueError,TypeError):path.unlink(missing_ok=True)
 def take_commands(self,coin):
  actions=[]
  for path in sorted(self.directory.glob('command-*.json'))[:32]:
   try:
    data=read_json(path)
    if data.get('profile')!=self.profile:continue
    path.unlink(missing_ok=True)
    if data.get('schema')!=1 or data.get('pid')!=os.getpid() or data.get('nonce')!=self.nonce or data.get('coin')!=coin or not fresh(data.get('time'),10):continue
    if data.get('action') in ACTIONS:actions.append((data['time'],{'stop':1,'quit':2}.get(data['action'],0),path.name,data['action']))
   except (OSError,ValueError,TypeError):continue
  self.prune();return [entry[3] for entry in sorted(actions)]
 def close(self):
  if self.closed:return
  self.path.unlink(missing_ok=True)
  if self.owner:fcntl.flock(self.lease,fcntl.LOCK_UN)
  self.lease.close();self.owner=False;self.closed=True
