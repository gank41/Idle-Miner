"""Provider errors must not publish an invalid market value as a fresh quote."""
import sys,time,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from PySide6.QtCore import QCoreApplication
from core import DEFAULTS
from network import Network
class NetworkTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.qt=QCoreApplication.instance() or QCoreApplication([])
 def response(self,amount):
  results=[];worker=Network();worker.ready.connect(results.append)
  settings=dict(DEFAULTS,pool_stats=False)
  with patch('network.get',return_value={'data':{'base':'LTC','currency':'USD','amount':amount}}):
   worker.fetch('fixture',settings);end=time.monotonic()+3
   while not results and time.monotonic()<end:self.qt.processEvents();time.sleep(.01)
  self.assertTrue(results,'Worker must finish and publish an outcome')
  return results[0]
 def test_bad_price_is_unavailable(self):
  for amount in ('0','-1','nan',None):
   with self.subTest(amount=amount):
    result=self.response(amount);self.assertIsNone(result['price']);self.assertTrue(result['errors'])
 def test_valid_price_is_published(self):
  result=self.response('68.25');self.assertEqual(result['price'],68.25);self.assertEqual(result['errors'],[])
