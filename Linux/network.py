import json,uuid,urllib.request,urllib.parse,threading
from PySide6.QtCore import QObject,Signal
from core import number,payload,pool_snapshot,valid_wallet
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*a,**kw):return None

def get(url):
 if urllib.parse.urlsplit(url).hostname not in ('api.coinbase.com','api.unmineable.com') or not url.startswith('https://'):raise ValueError('Unexpected API URL')
 req=urllib.request.Request(url,headers={'User-Agent':'IdleMinerLinux/1.5'})
 with urllib.request.build_opener(NoRedirect).open(req,timeout=12) as r:
  raw=r.read(2_000_001)
  if len(raw)>2_000_000:raise ValueError('Response too large')
  return json.loads(raw)
class Network(QObject):
 ready=Signal(object)
 def fetch(self,key,s):
  def run():
   result={'key':key,'price':None,'pool':None,'errors':[]}
   coin=s['coin']
   try:
    d=get(f'https://api.coinbase.com/v2/prices/{coin}-USD/spot')['data']
    if d['base']!=coin or d['currency']!='USD':raise ValueError('Currency mismatch')
    spot=number(d['amount'])
    if spot<=0:raise ValueError('Invalid price')
    result['price']=spot
   except Exception:result['errors'].append('Price unavailable; retrying automatically.')
   if s['pool_stats'] and valid_wallet(s['address'],coin):
    try:
     a=get('https://api.unmineable.com/v4/address/'+urllib.parse.quote(s['address'],safe='')+'?coin='+coin)
     d=payload(a)
     if d['address']!=s['address']:raise ValueError('Address mismatch')
     account=str(uuid.UUID(d['uuid']))
     stats=get(f'https://api.unmineable.com/v4/account/{account}/stats')
     result['pool']=pool_snapshot(a,stats,coin)
    except Exception:result['errors'].append('Pool stats unavailable; retrying automatically.')
   self.ready.emit(result)
  threading.Thread(target=run,daemon=True).start()
