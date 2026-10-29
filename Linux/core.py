"""Idle Miner Linux: platform-independent validation, mining policy and accounting."""
import hashlib, json, math, re, time
from dataclasses import dataclass

VERSION = '1.9'
BUILD = 12
DURATIONS = (15, 30, 60, 360, 720, 1440)
COINS = ('BTC','LTC','DOGE','ETH')
DEFAULTS = dict(coin='LTC', address='', wallets=dict.fromkeys(COINS,''), idle_threads=4, pause_active=False, pool_stats=True, show_dock=True, show_menu_bar=True, start_mining_at_login=False)
def now():
    return time.clock_gettime(time.CLOCK_BOOTTIME) if hasattr(time,'CLOCK_BOOTTIME') else time.monotonic()

def keccak256(data):
    """Ethereum Keccak-256 (legacy 0x01 padding, distinct from SHA3-256).

    Keccak-f[1600], little-endian lanes; used for EIP-55 addresses.
    https://eips.ethereum.org/EIPS/eip-55
    """
    mask=(1<<64)-1
    rotations=((0,36,3,41,18),(1,44,10,45,2),(62,6,43,15,61),(28,55,25,21,56),(27,20,39,8,14))
    rounds=(0x0000000000000001,0x0000000000008082,0x800000000000808a,0x8000000080008000,
      0x000000000000808b,0x0000000080000001,0x8000000080008081,0x8000000000008009,
      0x000000000000008a,0x0000000000000088,0x0000000080008009,0x000000008000000a,
      0x000000008000808b,0x800000000000008b,0x8000000000008089,0x8000000000008003,
      0x8000000000008002,0x8000000000000080,0x000000000000800a,0x800000008000000a,
      0x8000000080008081,0x8000000000008080,0x0000000080000001,0x8000000080008008)
    def rotate(v,n):return ((v<<n)|(v>>(64-n)))&mask
    padded=bytearray(data);padded.append(1)
    padded.extend(bytes((-len(padded))%136));padded[-1]|=0x80
    lanes=[0]*25
    for offset in range(0,len(padded),136):
        for i in range(17):lanes[i]^=int.from_bytes(padded[offset+8*i:offset+8*i+8],'little')
        for rc in rounds:
            columns=[lanes[x]^lanes[x+5]^lanes[x+10]^lanes[x+15]^lanes[x+20] for x in range(5)]
            delta=[columns[(x-1)%5]^rotate(columns[(x+1)%5],1) for x in range(5)]
            b=[0]*25
            for x in range(5):
                for y in range(5):b[y+5*((2*x+3*y)%5)]=rotate(lanes[x+5*y]^delta[x],rotations[x][y])
            for x in range(5):
                for y in range(5):lanes[x+5*y]=b[x+5*y]^((~b[(x+1)%5+5*y])&b[(x+2)%5+5*y])
            lanes[0]^=rc
    return b''.join(v.to_bytes(8,'little') for v in lanes)[:32]

def valid_wallet(s, coin):
    if coin not in COINS or not s or len(s)>90 or not s.isascii() or s.strip()!=s: return False
    if coin=='ETH':
        if not re.fullmatch(r'0x[0-9a-fA-F]{40}',s) or int(s[2:],16)==0:return False
        body=s[2:]
        if body in (body.lower(),body.upper()):return True
        digest=keccak256(body.lower().encode('ascii')).hex()
        return all(c==c.upper() if int(digest[i],16)>=8 else c==c.lower() for i,c in enumerate(body))
    if s.lower().startswith(('bc1','ltc1')):
        hrp={'BTC':'bc','LTC':'ltc'}.get(coin,'')
        if not hrp or s not in (s.lower(),s.upper()) or not s.lower().startswith(hrp+'1'): return False
        try: values=['qpzry9x8gf2tvdw0s3jn54khce6mua7l'.index(c) for c in s.lower()[len(hrp)+1:]]
        except ValueError: return False
        if len(values)<7 or values[0]!=0: return False
        chk=1
        for v in [ord(c)>>5 for c in hrp]+[0]+[ord(c)&31 for c in hrp]+values:
            top=chk>>25; chk=((chk&0x1ffffff)<<5)^v
            for i,g in enumerate((0x3b6a57b2,0x26508e6d,0x1ea119fa,0x3d4233dd,0x2a1462b3)):
                if (top>>i)&1: chk^=g
        acc=bits=0; program=[]
        for v in values[1:-6]:
            acc=((acc<<5)|v)&0xffff; bits+=5
            while bits>=8:
                bits-=8; program.append((acc>>bits)&255)
        return chk==1 and bits<5 and ((acc<<(8-bits))&255)==0 and len(program) in (20,32)
    n=0
    try:
        for c in s: n=n*58+'123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz'.index(c)
    except ValueError: return False
    b=b'\0'*(len(s)-len(s.lstrip('1')))+n.to_bytes((n.bit_length()+7)//8,'big')
    return len(b)==25 and b[0] in {'BTC':(0,5),'LTC':(48,50),'DOGE':(30,)}[coin] and b[-4:]==hashlib.sha256(hashlib.sha256(b[:-4]).digest()).digest()[:4]

def validated(s):
    result={**DEFAULTS,**s}
    if result['coin'] not in COINS: raise ValueError('Choose BTC, LTC, DOGE or ETH.')
    if type(result['idle_threads']) is not int or result['idle_threads'] not in (2,4,8,12): raise ValueError('Invalid thread count.')
    for key in ('pause_active','pool_stats','show_dock','show_menu_bar','start_mining_at_login'):
        if type(result[key]) is not bool: raise ValueError('Invalid settings.')
    if not result['show_dock'] and not result['show_menu_bar']: raise ValueError('Keep the window or menu bar visible.')
    supplied=s.get('wallets',{})
    if not isinstance(supplied,dict): raise ValueError('Invalid saved wallets.')
    wallets={coin:supplied.get(coin,'') for coin in COINS}
    if 'wallets' not in s and result['address']: wallets[result['coin']]=result['address']
    for coin,address in wallets.items():
        if not isinstance(address,str) or (address and not valid_wallet(address,coin)): raise ValueError('The receive address or its checksum does not match '+coin+'. Use its native network.')
    result['wallets']=wallets;result['address']=wallets[result['coin']]
    return {k:result[k] for k in DEFAULTS}

class SessionClock:
    def __init__(self):
        self.launched=now(); self.started=None; self.wall=None; self.frozen=0; self.hashing=0; self.last=None; self.was_hashing=False
    def start(self,t=None,wall=None):
        self.started=now() if t is None else t; self.wall=time.time() if wall is None else wall
        self.frozen=0;self.hashing=0;self.last=self.started;self.was_hashing=False
    def elapsed(self,t=None):
        return self.frozen if self.started is None else max(0,(now() if t is None else t)-self.started)
    def sample(self,active,t=None):
        t=now() if t is None else t
        if self.last is not None and self.was_hashing and 0<=t-self.last<=10:self.hashing+=t-self.last
        self.last=t;self.was_hashing=active
    def stop(self,t=None):
        self.sample(False,t);self.frozen=self.elapsed(t);self.started=None
    def uptime(self):return max(0,now()-self.launched)

def duration(seconds):
    seconds=int(max(0,seconds));days,seconds=divmod(seconds,86400);hours,seconds=divmod(seconds,3600);minutes,seconds=divmod(seconds,60)
    return (str(days)+'d ' if days else '')+f'{hours}:{minutes:02}:{seconds:02}'

@dataclass
class Environment:
    idle: bool=False
    idle_known: bool=False
    on_ac: bool=True
    hot: bool=False
    warm: bool=False
    memory_low: bool=False
    cores: int=4

def threads(s,e,boost=False,ceiling=12):
    if not e.on_ac or e.hot or e.memory_low: return 0
    if (not boost and not (e.idle_known and e.idle)) or e.warm: return 0 if s['pause_active'] else 1
    return min(s['idle_threads'],max(1,e.cores-2),ceiling)

def config(s,n,benchmark=False):
    if not 1<=n<=12: raise ValueError('Invalid engine threads')
    if not benchmark and not valid_wallet(s['address'],s['coin']): raise ValueError('Save your public receive address in Settings first.')
    result={'watch':True,'autosave':False,'background':False,'colors':False,'donate-level':1,
      'pools':[] if benchmark else [{'url':'rx.unmineable.com:443','user':f"{s['coin']}:{s['address']}.IdleMinerLinux",'pass':'x','tls':True,'keepalive':True,'algo':'rx/0'}],
      'cpu':{'enabled':True,'priority':1,'yield':True,'huge-pages':False,'rx':[-1]*n,'*':False},
      'randomx':{'init':min(n,2),'mode':'fast','rdmsr':False,'wrmsr':False,'1gb-pages':False},
      'opencl':False,'cuda':False,'http':{'enabled':False},'print-time':5,'retries':3,'retry-pause':10}
    if benchmark: result['benchmark']={'size':'1M','submit':False}
    return result

class Work:
    def __init__(self):
        self.accepted=0; self.rejected=0; self.history=[]; self.started=0; self.rate=None; self.updated=0
        self.connected=False; self.issue=''; self.donating=False; self.offline=False; self.last_positive=0
    def engine_started(self,offline=False):
        self.started=now(); self.rate=None; self.updated=0; self.connected=False; self.issue=''; self.offline=offline; self.donating=False; self.last_positive=0
        self.history.append((self.started,None))
    def threads_changed(self):
        self.started=now(); self.rate=None; self.updated=0; self.last_positive=0; self.history.append((self.started,None))
    def consume(self,line,t=None):
        t=now() if t is None else t
        lower=line.lower()
        if 'donate started' in lower: self.donating=True
        if 'donate finished' in lower: self.donating=False
        if 'new job from' in lower and not self.donating: self.connected=True; self.issue=''
        if not self.offline and not self.donating and any(x in lower for x in ('connect error','no active pools','login error','read error','write error','connection reset','connection refused','timed out','dns error','tls handshake failed')):
            self.connected=False; self.issue='Pool connection problem — see the log'
        m=re.search(r'speed 10s/60s/15m\s+(\S+)',lower)
        if m:
            try: rate=float(m[1])
            except ValueError: rate=None
            self.rate=rate if rate is not None and math.isfinite(rate) and rate>=0 else None
            self.updated=t; self.history.append((t,self.rate)); self.history=self.history[-360:]
            if self.rate and self.rate>0: self.last_positive=t
        if not self.offline and not self.donating:
            if 'accepted (' in lower: self.accepted+=1; self.connected=True; self.issue=''
            if 'rejected (' in lower: self.rejected+=1
    def health(self,requested,running,stopping=False,fatal='',reporting='',t=None):
        t=now() if t is None else t
        if fatal: return 'red',fatal
        if not requested: return 'gray','Paused or stopped'
        if stopping or not running: return 'gray','Starting or changing thread count…'
        if self.issue or reporting: return 'red',self.issue or reporting
        if self.rate and t-self.updated<=30 and (self.offline or self.connected):
            return 'green','Offline benchmark working — no earnings' if self.offline else 'Mining is working — fresh hashrate and pool connection'
        if (self.last_positive and t-self.last_positive>30) or (self.updated and t-self.updated>30) or t-self.started>180: return 'red','No fresh mining activity — see the log'
        return 'gray','Starting — waiting for mining activity…'

def payload(r):
    if r.get('success') is not True or not isinstance(r.get('data'),dict): raise ValueError('Invalid pool response')
    return r['data']
def number(v):
    n=float(v)
    if isinstance(v,bool) or not math.isfinite(n) or n<0: raise ValueError('Invalid amount')
    return n

def pool_snapshot(a,s,coin):
    a,s=payload(a),payload(s)
    if s.get('coin')!=coin or s.get('network')!=coin or a.get('network')!=coin: raise ValueError('Wrong pool currency/network')
    result={k:number(s[k]) for k in ('balance','paid','payment_threshold')}
    if result['payment_threshold']<=0: raise ValueError('Invalid payout minimum')
    result['payable']=number(a['balance_payable']); result['auto']=a.get('auto')
    result['rewards']=number(s['rewarded']['past_24h']) if s.get('rewarded',{}).get('past_24h') is not None else None
    result['issue']=a.get('enabled') is False or any(v is True for v in a.get('err_flags',{}).values())
    return result
