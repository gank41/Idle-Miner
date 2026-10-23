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

class PoolAddressTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):cls.qt=QCoreApplication.instance() or QCoreApplication([])
 def pool_response(self,coin,saved,reported):
  results=[];worker=Network();worker.ready.connect(results.append)
  settings=dict(DEFAULTS,coin=coin,address=saved,pool_stats=True)
  def fixture(url):
   if url.startswith('https://api.coinbase.com/'):
    return {'data':{'base':coin,'currency':'USD','amount':'2000.00'}}
   if url.startswith('https://api.unmineable.com/v4/address/'):
    return {'success':True,'data':{'address':reported,'uuid':'01234567-89ab-cdef-0123-456789abcdef','network':coin,'balance_payable':'0.1','auto':True,'enabled':True,'err_flags':{}}}
   if url=='https://api.unmineable.com/v4/account/01234567-89ab-cdef-0123-456789abcdef/stats':
    return {'success':True,'data':{'coin':coin,'network':coin,'balance':'0.1','paid':'0','payment_threshold':'0.01','rewarded':{'past_24h':'0.02'}}}
   raise AssertionError('Unexpected fixture URL')
  with patch('network.get',side_effect=fixture):
   worker.fetch('address-fixture',settings);end=time.monotonic()+3
   while not results and time.monotonic()<end:self.qt.processEvents();time.sleep(.01)
  self.assertTrue(results,'Worker must finish and publish an outcome')
  return results[0]
 def test_eth_provider_can_normalize_address_case(self):
  saved='0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'
  for reported in (saved,saved.lower(),'0x'+saved[2:].upper()):
   with self.subTest(reported=reported):
    result=self.pool_response('ETH',saved,reported)
    self.assertIsNotNone(result['pool']);self.assertEqual(result['pool']['balance'],.1);self.assertEqual(result['errors'],[])
 def test_eth_provider_different_or_malformed_address_is_rejected(self):
  saved='0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed'
  for reported in ('0x8617E340B3D01FA5F11F306F4090FD50E238070D','0x5AAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',saved[:-1],None,42,'ethereum:'+saved):
   with self.subTest(reported=reported):
    result=self.pool_response('ETH',saved,reported);self.assertIsNone(result['pool']);self.assertTrue(result['errors'])
 def test_non_eth_provider_address_matching_remains_exact(self):
  saved='LKDyUEtTR1HXamkiEphisSiBJu6o3ZPE34'
  result=self.pool_response('LTC',saved,saved);self.assertIsNotNone(result['pool']);self.assertEqual(result['errors'],[])
  result=self.pool_response('LTC',saved,saved.lower());self.assertIsNone(result['pool']);self.assertTrue(result['errors'])
