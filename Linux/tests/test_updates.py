import copy, io, json, sys, threading, unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from updates import parse_manifest, newer, safe_url, fetch_manifest, check_async, MANIFEST_URL
MANIFEST={'schemaVersion':1,'version':'1.8','build':11,'releaseNotesURL':'https://idleminer.app/releases/v1.8.html','platforms':{'linux':{'url':'https://idleminer.app/downloads/v1.8/Idle-Miner-1.8-Linux.tar.gz','sha256':'a'*64},'macos':{'url':'https://idleminer.app/downloads/v1.8/Idle-Miner-1.8.dmg','sha256':'b'*64}}}
class UpdateTests(unittest.TestCase):
 def test_numeric_version_and_build(self):
  self.assertTrue(newer('1.10',1,'1.9',99));self.assertTrue(newer('1.8',12,'1.8',11));self.assertFalse(newer('1.8',10,'1.8',11));self.assertFalse(newer('1.8',11,'1.8.0',11))
 def test_manifest_valid(self):
  self.assertEqual(parse_manifest(MANIFEST)['url'],MANIFEST['platforms']['linux']['url'])
 def test_reject_unsafe_urls(self):
  for value in ['http://idleminer.app/a','https://idleminer.app.evil/a','https://evil.test/a','https://user@idleminer.app/a','https://idleminer.app:444/a','https://idleminer.app//evil/a','https://idleminer.app/a?x=1','https://idleminer.app/a#x','https://idleminer.app/a/../b','https://idleminer.app/%2e%2e/x','file:///tmp/file']:
   with self.subTest(value=value):self.assertFalse(safe_url(value))
 def test_reject_bad_schema_version_hash_platform(self):
  for edit in [lambda d:d.update(schemaVersion=2),lambda d:d.update(version='latest'),lambda d:d.update(build=True),lambda d:d['platforms']['linux'].update(sha256='x'*64),lambda d:d['platforms'].pop('linux'),lambda d:d.update(releaseNotesURL='https://evil.test/')]:
   d=copy.deepcopy(MANIFEST);edit(d)
   with self.assertRaises(ValueError):parse_manifest(d)
 def test_fetch_is_bounded_and_redirects_rejected(self):
  class Response(io.BytesIO):
   def geturl(self):return MANIFEST_URL+'.sig'
  for raw,url,good in [(json.dumps(MANIFEST).encode(),MANIFEST_URL,True),(b' ' * 65537,MANIFEST_URL,False),(json.dumps(MANIFEST).encode(),'https://evil.test/',False)]:
   response=Response(raw);response.geturl=lambda:url
   with patch('updates.verify_manifest'),patch('updates.urllib.request.build_opener') as opener:
    opener.return_value.open.side_effect=[response,Response(b'signature')]
    if good:self.assertEqual(fetch_manifest()['version'],'1.8')
    else:
     with self.assertRaises(ValueError):fetch_manifest()
 def test_async_failure_reports_offline_and_rate_limit(self):
  for error,expected in [(URLError('offline'),'connection'),(HTTPError(MANIFEST_URL,429,'busy',{},io.BytesIO()),'rate limited')]:
   finished=threading.Event();results=[]
   def receive(result):results.append(result);finished.set()
   with patch('updates.fetch_manifest',side_effect=error):
    check_async(receive);self.assertTrue(finished.wait(2))
   self.assertIsNone(results[0]['manifest']);self.assertIn(expected,results[0]['error'])
if __name__=='__main__':unittest.main()
