"""Explicit signed updates. Download and native preparation happen before shutdown."""
import ast, base64, contextlib, fcntl, hashlib, json, os, re, shutil, stat, subprocess, sys, tarfile, tempfile, threading, time, uuid, urllib.parse, urllib.request, urllib.error
from pathlib import Path
MANIFEST_URL='https://idleminer.app/updates/stable.json'
MAX_BYTES=65536
MAX_ARCHIVE_BYTES=128*1024*1024
MAX_UNPACKED_BYTES=512*1024*1024
MAX_MEMBERS=8192
# The release signing key is pinned in the installed application, never the manifest.
PUBLIC_KEY='eJ09A18pAdxNHEU6i9b1hp+tnJ5udezI9fJW5uH03D8='
EXECUTABLES=('xmrig','idle-monitor','miner-supervisor')
REQUIRED_FILES=('app.py','core.py','coordination.py','shared_tray.py','updates.py','startup.py','platform_linux.py','network.py','icon.png',*EXECUTABLES)
PROFILES=('default','BTC','LTC','DOGE','ETH')
class UpdateCancelled(Exception):pass

def cancelled(event):
 if event.is_set():raise UpdateCancelled('Update cancelled. Your installed app has not changed.')


def safe_url(value):
 if not isinstance(value,str) or len(value)>2048 or any(ord(c)<33 or ord(c)>126 for c in value):return False
 try:
  p=urllib.parse.urlsplit(value)
  return p.scheme=='https' and p.netloc=='idleminer.app' and p.hostname=='idleminer.app' and p.username is None and p.password is None and p.port is None and not p.query and not p.fragment and p.path.startswith('/') and not p.path.startswith('//') and '\\' not in p.path and '%' not in p.path and all(part not in ('.','..') for part in p.path.split('/'))
 except ValueError:return False

def version_parts(version):
 if not isinstance(version,str) or not re.fullmatch(r'[0-9]{1,6}(?:\.[0-9]{1,6}){0,3}',version):raise ValueError('Invalid update version')
 parts=[int(v) for v in version.split('.')]
 return tuple(parts+[0]*(4-len(parts)))

def newer(version,build,current_version,current_build):
 return (version_parts(version),build)>(version_parts(current_version),current_build)

def parse_manifest(data):
 try:
  if not isinstance(data,dict) or type(data['schemaVersion']) is not int or data['schemaVersion']!=1:raise ValueError('Unsupported update manifest')
  version_parts(data['version'])
  if type(data['build']) is not int or not 0<data['build']<2**31:raise ValueError('Invalid update build')
  if not safe_url(data['releaseNotesURL']) or not urllib.parse.urlsplit(data['releaseNotesURL']).path.startswith('/releases/'):raise ValueError('Invalid release notes URL')
  linux=data['platforms']['linux'];url=linux['url']
  if not safe_url(url) or not urllib.parse.urlsplit(url).path.startswith('/downloads/') or not urllib.parse.urlsplit(url).path.endswith('-Linux.tar.gz'):raise ValueError('Invalid Linux download URL')
  if not isinstance(linux['sha256'],str) or not re.fullmatch('[a-fA-F0-9]{64}',linux['sha256']):raise ValueError('Invalid Linux download checksum')
  notes=data.get('releaseNotesText','Release notes were not supplied for this release.')
  if not isinstance(notes,str) or len(notes)>12000 or any(ord(c)<32 and c not in '\n\t\r' for c in notes):raise ValueError('Invalid release notes')
  # Legacy manifests remain discoverable, but cannot pass install_metadata.
  return dict(version=data['version'],build=data['build'],releaseNotesURL=data['releaseNotesURL'],releaseNotesText=notes,url=url,sha256=linux['sha256'].lower(),length=linux.get('length'),edSignature=linux.get('edSignature'))
 except (KeyError,TypeError,AttributeError) as exc:raise ValueError('Invalid update manifest') from exc

class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None

def fetch_bytes(url,maximum,accept):
 request=urllib.request.Request(url,headers={'User-Agent':'IdleMinerLinux/1.9','Accept':accept})
 with urllib.request.build_opener(NoRedirect).open(request,timeout=12) as response:
  if response.geturl()!=url:raise ValueError('Unexpected update redirect')
  raw=response.read(maximum+1)
  if len(raw)>maximum:raise ValueError('Update metadata too large')
  return raw

def fetch_manifest():
 raw=fetch_bytes(MANIFEST_URL,MAX_BYTES,'application/json')
 signature=fetch_bytes(MANIFEST_URL+'.sig',512,'text/plain')
 verify_manifest(raw,signature)
 return parse_manifest(json.loads(raw))

def verify_manifest(raw,signature,public_key=PUBLIC_KEY):
 if not isinstance(signature,bytes) or len(signature)>512 or not isinstance(raw,bytes) or len(raw)>MAX_BYTES:raise ValueError('Invalid signed update metadata')
 try:encoded=signature.decode('ascii').strip()
 except UnicodeDecodeError as exc:raise ValueError('Invalid manifest signature') from exc
 release=dict(url=MANIFEST_URL,sha256=hashlib.sha256(raw).hexdigest(),length=len(raw),edSignature=encoded)
 with tempfile.TemporaryDirectory(prefix='idle-miner-manifest-') as directory:
  path=Path(directory)/'manifest';path.write_bytes(raw);verify_archive(path,release,public_key)

def check_async(callback):
 def run():
  try:result={'manifest':fetch_manifest(),'error':''}
  except urllib.error.HTTPError as error:
   error.close();result={'manifest':None,'error':'The update service is busy or rate limited. Wait a moment and try again.' if error.code==429 else 'The update service is temporarily unavailable. Try again later.'}
  except Exception:result={'manifest':None,'error':'Could not check for updates. Check your connection and try again. The update service may be temporarily unavailable.'}
  callback(result)
 threading.Thread(target=run,daemon=True).start()


class AutomaticUpdates:
 """One signed discovery per shared interval; never downloads or touches mining.

 The lease spans the request. The attempt is committed before I/O so crashes and
 service errors cannot make other currencies retry. Boottime survives suspend
 and keeps a wall-clock rollback from causing extra checks in the same boot.
 """
 def __init__(self,state):
  from coordination import SettingsStore
  self.state=Path(state);self.store=SettingsStore(self.state);self.path=self.state/'automatic-updates.json'
 def _load(self):
  try:
   data=json.loads(self.path.read_text())
   return data if isinstance(data,dict) else {}
  except (OSError,ValueError):return {}
 def available(self,version,build):
  try:
   release=self._load().get('available')
   return release if release and newer(release['version'],release['build'],version,build) else None
  except (ValueError,TypeError,KeyError):return None
 def run_once(self,version,build,wall=None,uptime=None,boot=None):
  from coordination import atomic
  from core import now
  try:
   # No lock or state file is created while the opt-in is disabled.
   if not self.store.load()['automatic_update_checks']:return None
   with open(self.state/'automatic-updates.lock','a') as lease:
    try:fcntl.flock(lease,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:return None
    settings=self.store.load()
    if not settings['automatic_update_checks']:return None
    wall=time.time() if wall is None else wall;uptime=now() if uptime is None else uptime
    if boot is None:boot=Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    data=self._load();interval=86400 if settings['update_check_frequency']=='daily' else 604800
    previous=data.get('lastAttempt')
    if isinstance(previous,(int,float)):
     elapsed=max(0,wall-previous)
     if data.get('boot')==boot and isinstance(data.get('uptime'),(int,float)):elapsed=max(elapsed,uptime-data['uptime'])
     if elapsed<interval:return None
    data.update(lastAttempt=wall,uptime=uptime,boot=boot);atomic(self.path,data)
    release=fetch_manifest() # Ed25519 manifest authentication is mandatory here.
    if not self.store.load()['automatic_update_checks'] or not newer(release['version'],release['build'],version,build):return None
    install_metadata(release)
    identity=dict(version=release['version'],build=release['build'])
    prior=data.get('notified');notify=not prior or newer(identity['version'],identity['build'],prior['version'],prior['build'])
    if notify:data['notified']=identity;data['available']=identity
    atomic(self.path,data);return dict(release=identity,notify=notify)
  except Exception:return None # Automatic failures are intentionally silent.


def install_metadata(release):
 """Fail closed before network/build activity if signing metadata is unavailable."""
 if not isinstance(release,dict) or not safe_url(release.get('url')):raise ValueError('Invalid update URL')
 if type(release.get('length')) is not int or not 0<release['length']<=MAX_ARCHIVE_BYTES:raise ValueError('This release has no valid signed installer size. Try checking for updates later.')
 try:signature=base64.b64decode(release['edSignature'],validate=True)
 except (KeyError,ValueError,TypeError) as exc:raise ValueError('This release has no valid update signature. Try checking for updates later.') from exc
 if len(signature)!=64:raise ValueError('Invalid update signature')
 if not isinstance(release.get('sha256'),str) or not re.fullmatch('[a-f0-9]{64}',release['sha256']):raise ValueError('Invalid update checksum')
 return signature

def download_archive(release,path,cancel,progress=lambda text:None):
 install_metadata(release);path=Path(path)
 try:
  cancelled(cancel)
  request=urllib.request.Request(release['url'],headers={'User-Agent':'IdleMinerLinux/1.9','Accept':'application/gzip'})
  with urllib.request.build_opener(NoRedirect).open(request,timeout=15) as response, path.open('xb') as output:
   if response.geturl()!=release['url']:raise ValueError('Unexpected update redirect')
   total=0
   while True:
    cancelled(cancel);chunk=response.read(256*1024)
    if not chunk:break
    total+=len(chunk)
    if total>release['length']:raise ValueError('Installer exceeds the published size')
    output.write(chunk);progress(f'Downloading update… {total*100//release["length"]}%')
   if total!=release['length']:raise ValueError('Installer download was interrupted. Try again.')
  cancelled(cancel)
 except BaseException:
  path.unlink(missing_ok=True);raise

def verify_archive(path,release,public_key=PUBLIC_KEY):
 signature=install_metadata(release);path=Path(path)
 if path.stat().st_size!=release['length']:raise ValueError('Installer size does not match the release')
 digest=hashlib.sha256()
 with path.open('rb') as source:
  for chunk in iter(lambda:source.read(256*1024),b''):digest.update(chunk)
 if digest.hexdigest()!=release['sha256']:raise ValueError('Installer checksum failed. No update was installed.')
 try:raw=base64.b64decode(public_key,validate=True)
 except (ValueError,TypeError) as exc:raise ValueError('The installed update signing key is invalid') from exc
 if len(raw)!=32:raise ValueError('The installed update signing key is invalid')
 with tempfile.TemporaryDirectory(prefix='idle-miner-signature-') as directory:
  key=Path(directory)/'public.der';sig=Path(directory)/'signature';key.write_bytes(bytes.fromhex('302a300506032b6570032100')+raw);sig.write_bytes(signature)
  try:result=subprocess.run(['openssl','pkeyutl','-verify','-rawin','-pubin','-keyform','DER','-inkey',str(key),'-sigfile',str(sig),'-in',str(path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
  except (OSError,subprocess.TimeoutExpired) as exc:raise ValueError('OpenSSL with Ed25519 support is required to verify updates. Your app has not changed.') from exc
  if result.returncode:raise ValueError('Installer signature verification failed. No update was installed.')

def extract_archive(path,directory,cancel=None):
 """Extract ordinary files only, after checking every header and resource bound."""
 directory=Path(directory);directory.mkdir(mode=0o700,parents=True,exist_ok=True);seen=set();total=0
 with tarfile.open(path,'r:gz') as archive:
  for index,member in enumerate(archive):
   if cancel is not None:cancelled(cancel)
   parts=member.name.rstrip('/').split('/')
   if index>=MAX_MEMBERS or any(part in ('','.','..') for part in parts) or '\\' in member.name or len(member.name)>1024 or not (member.isdir() or member.isfile()) or member.name.rstrip('/') in seen:raise ValueError('The installer archive contains unsafe entries')
   seen.add(member.name.rstrip('/'));total+=member.size
   if member.size<0 or total>MAX_UNPACKED_BYTES:raise ValueError('The installer archive is too large')
   target=directory.joinpath(*parts)
   if member.isdir():target.mkdir(parents=True,exist_ok=True,mode=0o700);continue
   target.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
   with archive.extractfile(member) as source,target.open('xb') as output:
    remaining=member.size
    while remaining:
     if cancel is not None:cancelled(cancel)
     chunk=source.read(min(256*1024,remaining))
     if not chunk:raise ValueError('Incomplete installer archive')
     output.write(chunk);remaining-=len(chunk)
   target.chmod(0o600)
 roots=[p for p in directory.iterdir() if p.is_dir() and (p/'install.sh').is_file()]
 if len(roots)!=1 or len(list(directory.iterdir()))!=1:raise ValueError('Unexpected Linux installer layout')
 return roots[0]

def validate_stage(stage):
 stage=Path(stage)
 for name in REQUIRED_FILES:
  path=stage/name
  if path.is_symlink() or not path.is_file() or path.stat().st_size==0:raise ValueError('The prepared update is incomplete: '+name)
 for name in EXECUTABLES:
  if not os.access(stage/name,os.X_OK):raise ValueError('The prepared engine is not executable')

def prepare_update(release,workspace,cancel,progress=lambda text:None):
 from core import VERSION,BUILD
 if not newer(release['version'],release['build'],VERSION,BUILD):raise ValueError('Only a newer version of Idle Miner can be installed.')
 workspace=Path(workspace);archive=workspace/'release.tar.gz'
 download_archive(release,archive,cancel,progress);progress('Verifying signed installer…');verify_archive(archive,release);cancelled(cancel)
 source=extract_archive(archive,workspace/'source',cancel);stage=workspace/'installed'
 # This code is executed only after the complete archive passes pinned-key verification.
 progress('Preparing the update for this computer… This may take several minutes.')
 env={**os.environ,'IDLE_MINER_UPDATE':'1','IDLE_MINER_STAGE':str(stage)}
 log=workspace/'build.log'
 with log.open('wb') as output:
  process=subprocess.Popen(['/bin/bash',str(source/'install.sh')],cwd=source,env=env,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
  deadline=time.monotonic()+1800
  try:
   while process.poll() is None:
    if cancel.wait(.2):raise UpdateCancelled('Update cancelled. Your installed app has not changed.')
    if time.monotonic()>deadline:raise ValueError('Preparing the update timed out. Your installed app has not changed.')
  except BaseException:
   # This group contains only the isolated build, never any installed miner.
   import signal
   os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=10)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
   raise
 if process.returncode:
  detail=log.read_text(errors='replace')[-2400:]
  raise ValueError('The update could not be prepared. Your app is still installed.\n\n'+detail)
 cancelled(cancel);validate_stage(stage)
 # Check version without importing or running the staged app.
 core=(stage/'core.py').read_text()
 if not re.search(r'^VERSION\s*=\s*[\'\"]'+re.escape(release['version'])+r'[\'\"]\s*$',core,re.M) or not re.search(r'^BUILD\s*=\s*'+str(release['build'])+r'\s*$',core,re.M):raise ValueError('Installer version does not match the published release')
 return stage

@contextlib.contextmanager
def installation_locks(state,timeout=25):
 """Never unlink stable lease inodes; acquire quota only after apps release."""
 state=Path(state);state.mkdir(mode=0o700,parents=True,exist_ok=True);deadline=time.monotonic()+timeout
 names=['app.lock',*(coin+'.lock' for coin in PROFILES[1:]),*(profile+'.engine.lock' for profile in PROFILES),'quota.lock'];locks=[]
 try:
  while True:
   try:
    for name in names:
     fd=os.open(state/name,os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0),0o600);lock=os.fdopen(fd,'a');locks.append(lock)
     if os.fstat(fd).st_uid!=os.getuid():raise ValueError('Unsafe installation lock owner')
     fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    break
   except BlockingIOError:
    for lock in reversed(locks):lock.close()
    locks=[]
    if time.monotonic()>=deadline:raise TimeoutError('A currency window or mining supervisor is still running. Quit all currencies, then try again. Your installed app has not changed.')
    time.sleep(.1)
  yield
 finally:
  for lock in reversed(locks):lock.close()

def installed_version(root):
 path=Path(root)/'core.py'
 if path.stat().st_size>512*1024:raise ValueError('Installed version metadata is too large')
 values={}
 for statement in ast.parse(path.read_text()).body:
  if isinstance(statement,ast.Assign):
   for target in statement.targets:
    if isinstance(target,ast.Name) and target.id in ('VERSION','BUILD'):values[target.id]=ast.literal_eval(statement.value)
 version=values.get('VERSION');build=values.get('BUILD');version_parts(version)
 if type(build) is not int or not 0<build<2**31:raise ValueError('Invalid installed build metadata')
 return version,build

def replace_install(stage,root,state,timeout=25):
 """Atomic directory renames with rollback, in the exact original location."""
 stage=Path(stage);root=Path(root);state=Path(state);validate_stage(stage)
 if not root.is_absolute() or root.is_symlink() or not root.is_dir() or root.stat().st_uid!=os.getuid() or root in (Path('/'),Path.home()):raise ValueError('The installation folder cannot be safely replaced')
 if state.resolve()==root.resolve() or root.resolve() in state.resolve().parents:raise ValueError('Move settings outside the app folder before updating')
 token=uuid.uuid4().hex;candidate=root.parent/('.idle-miner-new-'+token);backup=root.parent/('.idle-miner-previous-'+token)
 try:
  shutil.copytree(stage,candidate,symlinks=False);validate_stage(candidate)
  with installation_locks(state,timeout):
   if not newer(*installed_version(candidate),*installed_version(root)):raise ValueError('A same or newer version is already installed. No files were changed.')
   os.replace(root,backup)
   try:os.replace(candidate,root)
   except BaseException:os.replace(backup,root);raise
  # Keep the complete previous install for manual recovery.
  shutil.rmtree(stage,ignore_errors=True)
  return backup
 finally:
  if candidate.exists():shutil.rmtree(candidate)

# Update handoffs live outside the install and settings. Display summaries are
# deliberately not authority for enabled state: each process acknowledges at
# the instant it handles the update quit command, before stopping its engine.
RESUME_TTL=120
RESUME_COINS=('BTC','LTC','DOGE','ETH')

def valid_token(token):return isinstance(token,str) and re.fullmatch('[a-f0-9]{32}',token) is not None

def private_directory(path):
 path=Path(path);path.mkdir(parents=True,exist_ok=True,mode=0o700);info=path.lstat()
 if not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode&0o077:raise ValueError('Unsafe update handoff directory')
 return path

def read_private(path):
 fd=os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0))
 with os.fdopen(fd,'rb') as stream:
  info=os.fstat(stream.fileno())
  if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode&0o077 or info.st_size>MAX_BYTES:raise ValueError('Unsafe update handoff file')
  raw=stream.read(MAX_BYTES+1)
  if len(raw)>MAX_BYTES:raise ValueError('Update handoff too large')
  data=json.loads(raw)
  if not isinstance(data,dict):raise ValueError('Invalid update handoff')
  return data

def write_private(path,data):
 path=Path(path);raw=json.dumps(data,ensure_ascii=True).encode('ascii')
 if len(raw)>MAX_BYTES:raise ValueError('Update handoff too large')
 temporary=path.with_name('.'+path.name+'.'+uuid.uuid4().hex)
 fd=os.open(temporary,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 try:
  with os.fdopen(fd,'wb') as stream:stream.write(raw)
  temporary.replace(path)
 finally:temporary.unlink(missing_ok=True)

def resume_directory(state,token):
 if not valid_token(token):raise ValueError('Invalid update handoff token')
 parent=private_directory(Path(state)/'update-handoffs-v1')
 return private_directory(parent/token)

def receipt_path(state,token):
 if not valid_token(token):raise ValueError('Invalid update handoff token')
 return private_directory(Path(state)/'update-handoffs-v1')/(token+'.receipt.json')

def valid_rows(rows,acknowledged=False):
 if not isinstance(rows,list) or not 1<=len(rows)<=len(PROFILES):return False
 seen=set()
 for row in rows:
  if not isinstance(row,dict) or row.get('profile') not in PROFILES or row['profile'] in seen or row.get('coin') not in RESUME_COINS:return False
  if type(row.get('pid')) is not int or row['pid']<=0 or not valid_token(row.get('nonce')):return False
  if acknowledged and type(row.get('enabled')) is not bool:return False
  seen.add(row['profile'])
 return True

def validate_resume(data,root,token,acknowledged=False):
 if type(data.get('schema')) is not int or data['schema']!=1 or data.get('token')!=token or not valid_token(token):raise ValueError('Invalid update handoff')
 created=data.get('created')
 if type(created) not in (int,float) or not 0<=time.time()-created<=RESUME_TTL:raise ValueError('Update handoff expired')
 if data.get('root')!=str(Path(root).resolve()):raise ValueError('Update handoff belongs to another installation')
 for key in ('sourceBuild','targetBuild'):
  if type(data.get(key)) is not int or not 0<data[key]<2**31:raise ValueError('Invalid update build')
 if not newer(data.get('targetVersion'),data['targetBuild'],data.get('sourceVersion'),data['sourceBuild']):raise ValueError('Update handoff is not a newer release')
 if not valid_rows(data.get('targets'),acknowledged) or data.get('launcher') not in [r['profile'] for r in data['targets']]:raise ValueError('Invalid update currencies')
 return data

def begin_resume(state,root,source_version,source_build,target_version,target_build,targets,launcher):
 token=uuid.uuid4().hex
 rows=[{key:row[key] for key in ('profile','coin','pid','nonce')} for row in targets]
 request=dict(schema=1,token=token,root=str(Path(root).resolve()),created=time.time(),sourceVersion=source_version,sourceBuild=source_build,targetVersion=target_version,targetBuild=target_build,targets=rows,launcher=launcher)
 validate_resume(request,root,token)
 if installed_version(root)!=(source_version,source_build):raise ValueError('The installed app changed. Check for updates again.')
 write_private(resume_directory(state,token)/'request.json',request)
 return token

def acknowledge_resume(state,root,token,profile,pid,nonce,coin,enabled):
 try:
  directory=resume_directory(state,token);request=validate_resume(read_private(directory/'request.json'),root,token)
  if installed_version(root)!=(request['sourceVersion'],request['sourceBuild']):return False
  if type(pid) is not int or type(enabled) is not bool or coin not in RESUME_COINS:return False
  target=next((r for r in request['targets'] if r['profile']==profile and r['pid']==pid and r['nonce']==nonce),None)
  if target is None:return False
  row=dict(profile=profile,pid=pid,nonce=nonce,coin=coin,enabled=enabled)
  # The first hook owns the decision; later Stop/Quit activity cannot rewrite it.
  path=directory/(profile+'.json');temporary=directory/('.ack-'+uuid.uuid4().hex)
  try:
   write_private(temporary,row);os.link(temporary,path,follow_symlinks=False)
  finally:temporary.unlink(missing_ok=True)
  return True
 except (OSError,ValueError,TypeError,KeyError,StopIteration):return False

def finalize_resume(state,root,token,timeout=10):
 directory=resume_directory(state,token);request=validate_resume(read_private(directory/'request.json'),root,token);deadline=time.monotonic()+timeout
 while True:
  rows=[]
  try:
   for target in request['targets']:
    row=read_private(directory/(target['profile']+'.json'))
    if not valid_rows([row],True) or any(row[key]!=target[key] for key in ('profile','pid','nonce')):raise ValueError('Invalid currency acknowledgement')
    rows.append(row)
   return validate_resume(dict(request,targets=rows),root,token,True)
  except FileNotFoundError:
   if time.monotonic()>=deadline:raise ValueError('A currency did not acknowledge update shutdown. No update was installed.')
   time.sleep(.05)

def publish_resume(state,root,plan):
 plan=validate_resume(plan,root,plan.get('token'),True)
 if installed_version(root)!=(plan['targetVersion'],plan['targetBuild']):raise ValueError('The installed update does not match the resume receipt')
 receipt=dict(plan,created=time.time(),remaining=[r['profile'] for r in plan['targets']],peersLaunched=False)
 write_private(receipt_path(state,plan['token']),receipt)
 return receipt

def consume_resume(state,root,token,profile,version,build):
 """Consume each profile once under a stable lock; launcher opens exact peers."""
 if not valid_token(token) or profile not in PROFILES:return None
 try:
  path=receipt_path(state,token);lock_path=path.with_suffix('.lock')
  fd=os.open(lock_path,os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0),0o600)
  with os.fdopen(fd,'a') as lock:
   info=os.fstat(lock.fileno())
   if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or info.st_mode&0o077:return None
   fcntl.flock(lock,fcntl.LOCK_EX)
   data=validate_resume(read_private(path),root,token,True)
   if (version,build)!=(data['targetVersion'],data['targetBuild']) or installed_version(root)!=(version,build):return None
   remaining=data.get('remaining')
   expected={r['profile'] for r in data['targets']}
   if not isinstance(remaining,list) or len(set(remaining))!=len(remaining) or any(p not in expected for p in remaining) or profile not in remaining or type(data.get('peersLaunched')) is not bool:return None
   row=next(r for r in data['targets'] if r['profile']==profile)
   peers=[]
   if profile==data['launcher'] and not data['peersLaunched']:
    peers=[{key:r[key] for key in ('profile','coin','enabled')} for r in data['targets'] if r['profile']!=profile and r['profile'] in remaining];data['peersLaunched']=True
   data['remaining'].remove(profile)
   if data['remaining']:write_private(path,data)
   else:path.unlink()
   return dict(coin=row['coin'],enabled=row['enabled'],peers=peers)
 except (OSError,ValueError,TypeError,KeyError,StopIteration):return None

def discard_resume(state,token):
 if not valid_token(token):return
 try:receipt_path(state,token).unlink(missing_ok=True);shutil.rmtree(resume_directory(state,token),ignore_errors=True)
 except (OSError,ValueError):pass


def request_shutdown(tray,targets,token=None):
 if token is not None:
  if not valid_token(token):raise ValueError('Invalid update handoff token')
  for row in targets:
   if not tray.send(row,'quit-update:'+token):raise ValueError('A currency could not receive update shutdown. Wait a moment and try again.')
  return
 for row in targets:
  if not tray.send(row,'stop'):raise ValueError('A currency could not receive Stop. Wait a moment and try again.')
 for row in targets:
  if not tray.send(row,'quit'):raise ValueError('A currency could not receive Quit. Wait a moment and try again.')

def helper_main(stage,root,state,workspace,token=None):
 """Detached helper remains available while installed files are replaced."""
 message='Updated successfully. Mining is stopped; choose Start when you are ready.';resume=None
 try:
  plan=finalize_resume(state,root,token) if token is not None else None
  if plan is not None and installed_version(stage)!=(plan['targetVersion'],plan['targetBuild']):raise ValueError('Prepared update does not match the resume handoff')
  replace_install(stage,root,state)
  if plan is not None:
   publish_resume(state,root,plan);resume=plan
   message='Updated successfully. Previously enabled currencies have resumed their automatic mining settings. Stopped currencies remain stopped.'
 except Exception as exc:
  discard_resume(state,token);message='The update was not installed or could not resume automatically. '+str(exc)
 state=Path(state);result=state/'update-result.json'
 try:
  write_private(result,{'message':message})
  arguments=[sys.executable,str(Path(root)/'app.py'),'--update-result']
  if resume is not None:
   arguments+=['--profile='+resume['launcher'],'--resume-update='+token]
  subprocess.Popen(arguments,cwd=root,start_new_session=True,close_fds=True)
 finally:
  if token is not None:
   try:shutil.rmtree(resume_directory(state,token),ignore_errors=True)
   except (OSError,ValueError):pass
  shutil.rmtree(workspace,ignore_errors=True)

if __name__=='__main__' and len(sys.argv) in (6,7) and sys.argv[1]=='--install-prepared':helper_main(*sys.argv[2:])
