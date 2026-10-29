"""Offline security and rollback tests. No network, wallets or miner processes."""
import base64, copy, hashlib, io, json, os, shutil, subprocess, sys, tarfile, tempfile, threading, unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import updates

class InstallUpdateTests(unittest.TestCase):
 def setUp(self):
  # macOS ships LibreSSL; Linux uses its supported OpenSSL system package.
  bundled=Path('/opt/homebrew/opt/openssl@3/bin')
  if sys.platform=='darwin' and (bundled/'openssl').exists():
   environment=patch.dict(os.environ,{'PATH':str(bundled)+os.pathsep+os.environ.get('PATH','')});environment.start();self.addCleanup(environment.stop)
  self.temp=tempfile.TemporaryDirectory();self.directory=Path(self.temp.name)
 def tearDown(self):self.temp.cleanup()
 def release(self,raw=b'release'):
  return dict(url='https://idleminer.app/downloads/v1.9/Idle-Miner-1.9-Linux.tar.gz',sha256=hashlib.sha256(raw).hexdigest(),length=len(raw),edSignature=base64.b64encode(bytes(64)).decode(),version='1.9',build=12,releaseNotesText='Fixed updates.')
 def test_install_requires_signed_metadata_and_plain_notes(self):
  from test_updates import MANIFEST
  for field,value in [('edSignature',None),('edSignature','a'),('length',True),('length',0),('length',updates.MAX_ARCHIVE_BYTES+1)]:
   release=self.release();release[field]=value
   with self.subTest(field=field,value=value),self.assertRaises(ValueError):updates.install_metadata(release)
  manifest=copy.deepcopy(MANIFEST);manifest['releaseNotesText']='Plain release notes';manifest['platforms']['linux'].update(length=7,edSignature=self.release()['edSignature'])
  parsed=updates.parse_manifest(manifest);self.assertEqual(parsed['releaseNotesText'],'Plain release notes');self.assertEqual(parsed['length'],7)
  manifest['releaseNotesText']='x'*12001
  with self.assertRaises(ValueError):updates.parse_manifest(manifest)
 def test_unsigned_or_tampered_manifest_cannot_be_parsed(self):
  with self.assertRaises(ValueError):updates.verify_manifest(b'{"version":"99"}',b'not a signature')
  key=self.directory/'manifest-key';public=self.directory/'manifest-public';raw=self.directory/'manifest';raw.write_bytes(b'{"schemaVersion":1}')
  subprocess.run(['openssl','genpkey','-algorithm','ed25519','-out',str(key)],check=True,stderr=subprocess.PIPE)
  subprocess.run(['openssl','pkey','-in',str(key),'-pubout','-outform','DER','-out',str(public)],check=True,stderr=subprocess.PIPE)
  signature=subprocess.run(['openssl','pkeyutl','-sign','-rawin','-inkey',str(key),'-in',str(raw)],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout
  pub=base64.b64encode(public.read_bytes()[-32:]).decode();encoded=base64.b64encode(signature)
  updates.verify_manifest(raw.read_bytes(),encoded,pub)
  with self.assertRaises(ValueError):updates.verify_manifest(b'{"schemaVersion":2}',encoded,pub)
 def test_preparation_refuses_downgrade_before_download(self):
  release=dict(self.release(),version='1.0',build=1)
  with patch('updates.download_archive',side_effect=AssertionError('A downgrade attempted a network download')),self.assertRaises(ValueError):updates.prepare_update(release,self.directory,threading.Event())
 def test_hash_length_signature_and_tampering_are_verified_with_real_openssl(self):
  key=self.directory/'private.pem';public=self.directory/'public.der';archive=self.directory/'update.tar.gz';archive.write_bytes(b'a signed release')
  subprocess.run(['openssl','genpkey','-algorithm','ed25519','-out',str(key)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
  subprocess.run(['openssl','pkey','-in',str(key),'-pubout','-outform','DER','-out',str(public)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
  signature=self.directory/'signature';subprocess.run(['openssl','pkeyutl','-sign','-rawin','-inkey',str(key),'-in',str(archive),'-out',str(signature)],check=True,stderr=subprocess.PIPE)
  release=self.release(archive.read_bytes());release['edSignature']=base64.b64encode(signature.read_bytes()).decode();pub=base64.b64encode(public.read_bytes()[-32:]).decode()
  updates.verify_archive(archive,release,pub)
  for mutated in [dict(release,sha256='0'*64),dict(release,length=100),dict(release,edSignature=base64.b64encode(bytes(64)).decode())]:
   with self.assertRaises(ValueError):updates.verify_archive(archive,mutated,pub)
  archive.write_bytes(b'a signed releasf')
  with self.assertRaises(ValueError):updates.verify_archive(archive,release,pub)
 def archive(self,members):
  path=self.directory/'archive.tar.gz'
  with tarfile.open(path,'w:gz') as archive:
   for name,kind in members:
    entry=tarfile.TarInfo(name);entry.type=kind
    if kind==tarfile.REGTYPE:entry.size=1;archive.addfile(entry,io.BytesIO(b'x'))
    else:entry.linkname='/tmp/escape';archive.addfile(entry)
  return path
 def test_archive_rejects_traversal_links_duplicate_and_resource_caps(self):
  for members in [[('../escape',tarfile.REGTYPE)],[('/escape',tarfile.REGTYPE)],[('root/link',tarfile.SYMTYPE)],[('root/link',tarfile.LNKTYPE)],[('root/pipe',tarfile.FIFOTYPE)],[('root/a',tarfile.REGTYPE),('root/a',tarfile.REGTYPE)]]:
   with self.subTest(members=members),self.assertRaises(ValueError):updates.extract_archive(self.archive(members),self.directory/'unpack')
  with patch.object(updates,'MAX_UNPACKED_BYTES',0),self.assertRaises(ValueError):updates.extract_archive(self.archive([('root/a',tarfile.REGTYPE)]),self.directory/'unpack')
  self.assertFalse((self.directory.parent/'escape').exists())
 def test_download_cancellation_and_short_response_leave_no_archive(self):
  release=self.release();path=self.directory/'download';cancel=threading.Event();cancel.set()
  class Response(io.BytesIO):
   def geturl(self):return release['url']
  for raw,event in [(b'release',cancel),(b'short',threading.Event()),(b'release-too-long',threading.Event())]:
   with patch('updates.urllib.request.build_opener') as opener:
    opener.return_value.open.return_value=Response(raw)
    with self.assertRaises((ValueError,updates.UpdateCancelled)):updates.download_archive(release,path,event)
   self.assertFalse(path.exists())
 def stage(self):
  stage=self.directory/'stage';stage.mkdir()
  for name in updates.REQUIRED_FILES:(stage/name).write_text('new')
  (stage/'core.py').write_text("VERSION = '9.0'\nBUILD = 1\n")
  for name in updates.EXECUTABLES:(stage/name).chmod(0o755)
  return stage
 def test_replace_preserves_custom_location_wallets_and_rolls_back(self):
  root=self.directory/'custom location'/'Installed Miner';root.mkdir(parents=True);(root/'app.py').write_text('old');(root/'core.py').write_text("VERSION = '1.0'\nBUILD = 1\n")
  state=self.directory/'state';state.mkdir();(state/'settings.json').write_text('wallet unchanged')
  stage=self.stage();updates.replace_install(stage,root,state,timeout=0)
  self.assertEqual((root/'app.py').read_text(),'new');self.assertEqual((state/'settings.json').read_text(),'wallet unchanged')
  stage=self.stage();(stage/'core.py').write_text("VERSION = '9.1'\nBUILD = 1\n");real_replace=os.replace;calls=[]
  def fail_stage(source,dest):
   calls.append(str(source))
   if Path(source).name.startswith('.idle-miner-new-'):raise OSError('simulated rename failure')
   return real_replace(source,dest)
  with patch('updates.os.replace',side_effect=fail_stage),self.assertRaises(OSError):updates.replace_install(stage,root,state,timeout=0)
  self.assertEqual((root/'app.py').read_text(),'new');self.assertEqual((state/'settings.json').read_text(),'wallet unchanged')
 def test_helper_rechecks_installed_version_before_replacing(self):
  root=self.directory/'installed';root.mkdir();(root/'app.py').write_text('newer install');(root/'core.py').write_text("VERSION = '10.0'\nBUILD = 1\n")
  state=self.directory/'state';state.mkdir();stage=self.stage()
  with self.assertRaises(ValueError):updates.replace_install(stage,root,state,timeout=0)
  self.assertEqual((root/'app.py').read_text(),'newer install')
 def test_live_engine_lease_prevents_replacement(self):
  root=self.directory/'installed';root.mkdir();(root/'app.py').write_text('old');(root/'core.py').write_text("VERSION = '1.0'\nBUILD = 1\n");state=self.directory/'state';state.mkdir();stage=self.stage()
  source="import fcntl,sys;f=open(sys.argv[1],'a');fcntl.flock(f,fcntl.LOCK_EX);print('locked',flush=True);sys.stdin.read()"
  with subprocess.Popen([sys.executable,'-c',source,str(state/'LTC.engine.lock')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True) as child:
   self.assertEqual(child.stdout.readline().strip(),'locked')
   try:
    with self.assertRaises(TimeoutError):updates.replace_install(stage,root,state,timeout=0)
    self.assertEqual((root/'app.py').read_text(),'old')
   finally:child.stdin.close();child.wait(timeout=5);child.stdout.close()
 def test_detached_helper_installs_exact_location_and_relaunches_stopped(self):
  workspace=self.directory/'work';workspace.mkdir();root=self.directory/'Custom install';root.mkdir();(root/'app.py').write_text('old');(root/'core.py').write_text("VERSION = '1.0'\nBUILD = 1\n")
  state=self.directory/'private-state';state.mkdir();(state/'settings.json').write_text('unchanged wallet')
  stage=self.stage();marker=self.directory/'relaunched.json'
  (stage/'app.py').write_text("import json,sys;from pathlib import Path;Path("+repr(str(marker))+").write_text(json.dumps(sys.argv))")
  helper=workspace/'helper.py';shutil.copy2(Path(updates.__file__),helper)
  result=subprocess.run([sys.executable,str(helper),'--install-prepared',str(stage),str(root),str(state),str(workspace)],capture_output=True,text=True,timeout=8)
  self.assertEqual(result.returncode,0,result.stderr)
  import time
  deadline=time.monotonic()+5
  while not marker.exists() and time.monotonic()<deadline:time.sleep(.02)
  self.assertTrue(marker.is_file());self.assertEqual(json.loads(marker.read_text()),[str(root/'app.py'),'--update-result']);self.assertEqual((state/'settings.json').read_text(),'unchanged wallet');self.assertFalse(workspace.exists());self.assertIn('Updated successfully',json.loads((state/'update-result.json').read_text())['message'])
 def test_stop_commands_precede_quit_for_all_profiles(self):
  rows=[{'profile':'BTC'},{'profile':'ETH'}];events=[]
  class Tray:
   def send(self,row,action):events.append((row['profile'],action));return True
  updates.request_shutdown(Tray(),rows)
  self.assertEqual(events,[('BTC','stop'),('ETH','stop'),('BTC','quit'),('ETH','quit')])
class InstallerStagingTests(unittest.TestCase):
 def test_stage_mode_never_touches_install_or_desktop_entries(self):
  with tempfile.TemporaryDirectory() as temporary:
   directory=Path(temporary);source=directory/'source';source.mkdir();home=directory/'home';home.mkdir();stage=directory/'staged';build=directory/'build'
   for relative in ('xmrig-build/xmrig','idle-build/idle-monitor','miner-supervisor'):
    path=build/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('binary')
   for name in ('app.py','core.py','coordination.py','shared_tray.py','updates.py','startup.py','platform_linux.py','network.py','icon.png','update_public_key.txt','README.txt','LICENSE.txt','supervisor.c'):(source/name).write_text('fixture')
   (source/'vendor').mkdir();(source/'vendor/xmrig-6.26.0.tar.gz').write_text('source');(source/'idle-helper').mkdir();(source/'idle-helper/main.cpp').write_text('helper')
   env={**os.environ,'HOME':str(home),'IDLE_MINER_BUILD':str(build),'IDLE_MINER_STAGE':str(stage),'IDLE_MINER_UPDATE':'1'}
   result=subprocess.run([sys.executable,str(Path(__file__).resolve().parents[1]/'install_files.py')],cwd=source,env=env,capture_output=True,text=True)
   self.assertEqual(result.returncode,0,result.stderr);self.assertTrue((stage/'app.py').is_file());self.assertTrue(os.access(stage/'xmrig',os.X_OK));self.assertFalse((home/'.local').exists());self.assertFalse((home/'.config').exists())

if __name__=='__main__':unittest.main()
