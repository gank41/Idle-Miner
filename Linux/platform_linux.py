"""Read-only Linux power, memory, heat and idle monitoring."""
import os, subprocess
from pathlib import Path
from PySide6.QtCore import QObject,QProcess,Slot
from PySide6.QtDBus import QDBusConnection,QDBusMessage,QDBus
from core import Environment,now

class Sensors(QObject):
    def __init__(self,root):
        super().__init__(); self.idle=False; self.known=False; self.last_total=None; self.busy_ticks=0; self.ceiling=12; self.hot=False; self.cpu=0; self.available_bytes=0
        self.idle_proc=None; self.idle_buffer=''; self.temps=[]
        self.virtual=subprocess.run(['systemd-detect-virt'],capture_output=True,text=True).returncode==0
        self.mutter=QDBusConnection.sessionBus().interface().isServiceRegistered('org.gnome.Mutter.IdleMonitor').value()
        if not self.mutter:
            self.idle_proc=QProcess(self);self.idle_proc.setProgram(str(root/'idle-monitor'))
            self.idle_proc.readyReadStandardOutput.connect(self.read_idle)
            self.idle_proc.finished.connect(self.idle_gone);self.idle_proc.start()
    @Slot()
    def read_idle(self):
        self.idle_buffer+=bytes(self.idle_proc.readAllStandardOutput()).decode(errors='replace')
        while '\n' in self.idle_buffer:
            line,self.idle_buffer=self.idle_buffer.split('\n',1)
            if line in ('ACTIVE','IDLE'):self.known=True;self.idle=line=='IDLE'
            elif line=='UNKNOWN':self.known=False;self.idle=False
    def idle_gone(self,*args):self.known=False;self.idle=False
    def sample(self,current_threads=0):
        if self.mutter:
            msg=QDBusMessage.createMethodCall('org.gnome.Mutter.IdleMonitor','/org/gnome/Mutter/IdleMonitor/Core','org.gnome.Mutter.IdleMonitor','GetIdletime')
            reply=QDBusConnection.sessionBus().call(msg,QDBus.CallMode.Block,250)
            args=reply.arguments();self.known=reply.type()!=QDBusMessage.MessageType.ErrorMessage and bool(args)
            self.idle=self.known and int(args[0])>=300000
        batteries=[];power=[]
        for device in Path('/sys/class/power_supply').glob('*'):
            try:
                kind=(device/'type').read_text().strip()
                if kind=='Battery': batteries.append((device/'status').read_text().strip())
                elif (device/'online').exists():power.append((device/'online').read_text().strip()=='1')
            except OSError: pass
        on_ac=any(power) or bool(batteries and all(x in ('Charging','Full') for x in batteries))
        if not batteries and not power:on_ac=True # desktop/VM; guest cannot see host battery
        self.temps=[]
        for f in list(Path('/sys/class/thermal').glob('thermal_zone*/temp'))+list(Path('/sys/class/hwmon').glob('hwmon*/temp*_input')):
            try:
                v=float(f.read_text())/1000
                if 0<v<150:self.temps.append(v)
            except (ValueError,OSError):pass
        high=max(self.temps,default=0)
        if high>=85:self.hot=True
        elif high<75:self.hot=False
        try:
            mem={k:int(v.split()[0]) for k,v in (line.split(':',1) for line in Path('/proc/meminfo').read_text().splitlines())}
            self.available_bytes=mem['MemAvailable']*1024
            low=mem['MemAvailable']<max(1024*1024,mem['MemTotal']*.10)
        except (OSError,KeyError,ValueError):low=True
        try:
            fields=list(map(int,Path('/proc/stat').read_text().splitlines()[0].split()[1:9]));total=sum(fields);idle=fields[3]+fields[4]
            if self.last_total:
                dt=total-self.last_total[0];di=idle-self.last_total[1];self.cpu=1-di/dt if dt>0 else 0
            self.last_total=(total,idle)
            self.busy_ticks=self.busy_ticks+1 if self.cpu>.85 and current_threads>1 else 0
            # Session-long backoff avoids repeatedly rebuilding RandomX under high load.
            if self.busy_ticks>=5:self.ceiling=max(1,current_threads//2);self.busy_ticks=0
        except (OSError,ValueError,IndexError):pass
        return Environment(self.idle,self.known,on_ac,self.hot,high>=75,low,os.cpu_count() or 1)
    def close(self):
        if self.idle_proc and self.idle_proc.state()!=QProcess.ProcessState.NotRunning:
            self.idle_proc.terminate();self.idle_proc.waitForFinished(2000)
