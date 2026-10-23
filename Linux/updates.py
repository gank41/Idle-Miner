"""Manual HTTPS update discovery. Never installs or alters mining state."""
import json, re, threading, urllib.parse, urllib.request, urllib.error
MANIFEST_URL='https://idleminer.app/updates/stable.json'
MAX_BYTES=65536

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
  return dict(version=data['version'],build=data['build'],releaseNotesURL=data['releaseNotesURL'],url=url,sha256=linux['sha256'].lower())
 except (KeyError,TypeError,AttributeError) as exc:raise ValueError('Invalid update manifest') from exc

class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None

def fetch_manifest():
 request=urllib.request.Request(MANIFEST_URL,headers={'User-Agent':'IdleMinerLinux/1.8','Accept':'application/json'})
 with urllib.request.build_opener(NoRedirect).open(request,timeout=12) as response:
  if response.geturl()!=MANIFEST_URL:raise ValueError('Unexpected update redirect')
  raw=response.read(MAX_BYTES+1)
  if len(raw)>MAX_BYTES:raise ValueError('Update manifest too large')
  return parse_manifest(json.loads(raw))

def check_async(callback):
 def run():
  try:result={'manifest':fetch_manifest(),'error':''}
  except urllib.error.HTTPError as error:
   error.close();result={'manifest':None,'error':'The update service is busy or rate limited. Wait a moment and try again.' if error.code==429 else 'The update service is temporarily unavailable. Try again later.'}
  except Exception:result={'manifest':None,'error':'Could not check for updates. Check your connection and try again. The update service may be temporarily unavailable.'}
  callback(result)
 threading.Thread(target=run,daemon=True).start()
