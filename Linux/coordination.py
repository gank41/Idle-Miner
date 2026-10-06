"""Stable process locks and shared quota/settings transactions; no wallet data in peer metadata."""
import fcntl, json, os, time
from pathlib import Path
from contextlib import contextmanager
from core import validated, COINS

@contextmanager
def transaction(path):
    with open(path,'a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        yield

def atomic(path,data):
    temp=path.with_name(path.name+'.'+str(os.getpid())+'.tmp')
    with open(temp,'w') as f:json.dump(data,f,indent=2);f.write('\n')
    temp.chmod(0o600);temp.replace(path)

class SettingsStore:
    def __init__(self,state):
        self.state=Path(state);self.state.mkdir(parents=True,exist_ok=True,mode=0o700);self.path=self.state/'settings.json'
    def load(self):
        return validated(json.loads(self.path.read_text()) if self.path.exists() else {})
    def save(self,edited,baseline):
        edited=validated(edited);baseline=validated(baseline)
        with transaction(self.state/'settings.lock'):
            current=self.load()
            for key in edited:
                if key in ('wallets','address'):continue
                if edited[key]!=baseline[key]:current[key]=edited[key]
            for coin in COINS:
                if edited['wallets'][coin]!=baseline['wallets'][coin]:current['wallets'][coin]=edited['wallets'][coin]
            current=validated(current);atomic(self.path,current);return current

class Coordinator:
    def __init__(self,state,profile='default'):
        if profile not in ('default',*COINS):raise ValueError('Invalid profile')
        self.state=Path(state);self.state.mkdir(parents=True,exist_ok=True,mode=0o700)
        self.profile=profile;self.lock=open(self.state/('app.lock' if profile=='default' else profile+'.lock'),'a')
        try:fcntl.flock(self.lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except Exception:self.lock.close();raise
        self.meta=self.state/(profile+'.peer.json');self.tx=self.state/'quota.lock';self.engine_lock=self.state/(profile+'.engine.lock')
        self.data=dict(profile=profile,pid=os.getpid(),coin='',request=0,reserved=0,budget=4,cores=4,order=time.time())
        with transaction(self.tx):
            with open(self.engine_lock,'a') as engine:
                try:fcntl.flock(engine,fcntl.LOCK_EX|fcntl.LOCK_NB)
                except BlockingIOError:self.lock.close();raise
            atomic(self.meta,self.data)
        self.closed=False
    def _peers(self):
        peers=[]
        for path in self.state.glob('*.peer.json'):
            if path==self.meta:continue
            profile=path.name.removesuffix('.peer.json')
            if profile not in ('default',*COINS):continue
            lockpath=self.state/('app.lock' if profile=='default' else profile+'.lock')
            with open(lockpath,'a') as lock:
                try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                except BlockingIOError:
                    try:peers.append(json.loads(path.read_text()))
                    except (OSError,ValueError):
                        # A live profile with unreadable metadata holds the entire capacity.
                        peers.append(dict(profile=profile,coin='',request=12,reserved=12,budget=1,cores=1,order=0))
                else:
                    with open(self.state/(profile+'.engine.lock'),'a') as engine:
                        try:fcntl.flock(engine,fcntl.LOCK_EX|fcntl.LOCK_NB)
                        except BlockingIOError:
                            try:
                                dead=json.loads(path.read_text());dead['request']=0;peers.append(dead)
                            except (OSError,ValueError):peers.append(dict(profile=profile,coin='',request=0,reserved=12,budget=1,cores=1,order=0))
                        else:path.unlink(missing_ok=True)
        return peers
    def update(self,coin,request,budget,cores):
        with transaction(self.tx):
            peers=self._peers();self.data.update(coin=coin,request=max(0,request),budget=budget,cores=cores)
            # The holder of an existing engine wins a currency switch collision.
            collision=any(p['coin']==coin and (p['reserved']>0 or (p['request']>0 and p['order']<self.data['order'])) for p in peers)
            if collision:self.data['request']=0
            active=sorted([p for p in peers+[self.data] if p['request']>0],key=lambda p:(p['order'],p['profile']))
            cap=min([budget,max(1,cores-2)]+[min(p['budget'],max(1,p['cores']-2)) for p in active])
            shares={p['profile']:0 for p in active};remaining=cap
            while remaining and active:
                progressed=False
                for p in active:
                    if remaining and shares[p['profile']]<p['request']:
                        shares[p['profile']]+=1;remaining-=1;progressed=True
                if not progressed:break
            target=shares.get(self.profile,0)
            free=max(0,cap-sum(p['reserved'] for p in peers))
            grant=min(target,free)
            # Reserve increases atomically before launching/reloading; release decreases only on READY/reap.
            self.data['reserved']=max(self.data['reserved'],grant)
            atomic(self.meta,self.data);return grant
    def reserve(self,n):
        with transaction(self.tx):self.data['reserved']=n;atomic(self.meta,self.data)
    def request_focus(self):atomic(self.state/(self.profile+'.focus.json'),{'time':time.time()})
    def take_focus(self):
        path=self.state/(self.profile+'.focus.json')
        if path.exists():path.unlink(missing_ok=True);return True
        return False
    def close(self):
        if self.closed:return
        with transaction(self.tx):self.meta.unlink(missing_ok=True);fcntl.flock(self.lock,fcntl.LOCK_UN);self.lock.close()
        self.closed=True
