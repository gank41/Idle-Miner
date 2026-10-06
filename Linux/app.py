#!/usr/bin/env python3
"""Idle Miner for Linux. A user session app; never a privileged mining service."""
import os,sys,json,signal,fcntl,shutil,uuid,time,subprocess
from pathlib import Path
from PySide6.QtCore import Qt,QTimer,QProcess,QUrl,QPointF,QDateTime,QLocale
from PySide6.QtGui import QIcon,QPixmap,QPainter,QPen,QColor,QFont,QDesktopServices,QAction
from PySide6.QtWidgets import (QApplication,QMainWindow,QWidget,QVBoxLayout,QHBoxLayout,QLabel,QPushButton,QMenu,QSystemTrayIcon,QDialog,QFormLayout,QLineEdit,QComboBox,QCheckBox,QDialogButtonBox,QMessageBox,QPlainTextEdit,QTabWidget,QWidgetAction,QScrollArea)
from core import VERSION,BUILD,DEFAULTS,COINS,DURATIONS,Work,SessionClock,duration,now,validated,valid_wallet,threads,config
from coordination import SettingsStore,Coordinator,atomic
from platform_linux import Sensors
from network import Network
ROOT=Path(__file__).resolve().parent
STATE=Path(os.environ.get('IDLE_MINER_STATE',str(Path.home()/'.config/idle-miner')))
PROFILE=next((arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--profile=')),'default')
AUTOSTART=Path.home()/'.config/autostart/idle-miner.desktop'

class Graph(QWidget):
 def __init__(self,work):
  super().__init__();self.work=work;self.setMinimumHeight(140)
 def paintEvent(self,event):
  p=QPainter(self);p.setRenderHint(QPainter.RenderHint.Antialiasing)
  color=self.palette().text().color();p.setPen(color)
  samples=[(t,v) for t,v in self.work.history if t>=now()-1800]
  p.drawText(12,22,'Hashrate · recent 30 minutes · H/s')
  if not samples:p.drawText(12,60,'Waiting for mining samples…');return
  highest=max((v or 0 for _,v in samples),default=1) or 1
  p.drawText(12,42,f'Peak {highest:.1f} H/s')
  left=max(samples[0][0],now()-1800);span=max(30,now()-left);last=None
  p.setPen(QPen(QColor('#29995c'),2))
  for t,v in samples:
   if v is None:last=None;continue
   pt=QPointF(12+(self.width()-24)*(t-left)/span,self.height()-12-(self.height()-66)*v/highest)
   if last is not None:p.drawLine(last,pt)
   last=pt

class Window(QMainWindow):
 def __init__(self,offline_test=False,profile=None,coordinator=None):
  super().__init__();self.profile=PROFILE if profile is None else profile;self.coordinator=coordinator or Coordinator(STATE,self.profile);self.store=SettingsStore(STATE);self.profile_state=STATE if self.profile=='default' else STATE/'profiles'/self.profile;self.profile_state.mkdir(parents=True,exist_ok=True,mode=0o700);self.clock=SessionClock();self.pending_coin=None;self.pending_resume=False;self.offline_test=offline_test;self.setWindowTitle('Idle Miner');self.setWindowIcon(QIcon(str(ROOT/'icon.png')));self.resize(760,900)
  screen=self.screen() or QApplication.primaryScreen()
  if screen:
   available=screen.availableGeometry();self.resize(min(760,max(1,available.width()-24)),min(900,max(1,available.height()-64)))
  self.setMinimumSize(min(560,self.width()),min(480,self.height()))
  self.settings=DEFAULTS.copy();self.fatal='';self.enabled=False;self.boost_until=0;self.benchmark_until=0;self.work=Work();self.current_threads=0;self.desired=0;self.stopping=False;self.quitting=False;self.proc=None;self.buffer='';self.engine_ready=False;self.change_deadline=0;self.engine_offline=False;self.logfile=None;self.logpath=None;self.configpath=self.profile_state/'engine.json';self.last_tick=now();self.resume_until=0
  self.quote=None;self.pool=None;self.quote_at=0;self.pool_at=0;self.net_error='';self.net_key='';self.net_busy=False;self.last_fetch=-1000
  STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
  try:
   self.settings=self.store.load()
   if self.profile!='default':self.settings['coin']=self.profile;self.settings['address']=self.settings['wallets'][self.profile]
  except Exception as e:self.fatal='Settings could not be loaded: '+str(e)
  self.setWindowTitle('Idle Miner · '+self.settings['coin'])
  self.sensors=Sensors(ROOT);self.network=Network();self.network.ready.connect(self.network_result)
  self.tabs=QTabWidget();self.setCentralWidget(self.tabs)
  page=QWidget();layout=QVBoxLayout(page);layout.setContentsMargins(22,18,22,18);layout.setSpacing(12)
  title=QLabel('Idle Miner');title_font=QFont(QApplication.font());title_font.setPointSize(23);title_font.setBold(True);title.setFont(title_font);layout.addWidget(title)
  self.state_label=QLabel('Stopped');state_font=QFont(QApplication.font());state_font.setPointSize(14);state_font.setWeight(QFont.Weight.DemiBold);self.state_label.setFont(state_font);layout.addWidget(self.state_label)
  self.health=QLabel();self.health.setWordWrap(True);layout.addWidget(self.health)
  row=QHBoxLayout()
  for title,action in [('Start',self.start),('Stop',self.stop),('Boost',self.boost_menu),('Settings',self.settings_dialog)]:
   button=QPushButton(title);button.clicked.connect(action);row.addWidget(button)
  layout.addLayout(row)
  self.rate=QLabel();self.shares=QLabel();self.timing=QLabel();self.timing.setWordWrap(True);layout.addWidget(self.rate);layout.addWidget(self.shares);layout.addWidget(self.timing)
  self.graph=Graph(self.work);layout.addWidget(self.graph)
  self.money=QLabel();self.money.setWordWrap(True);self.money.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse);layout.addWidget(self.money)
  row=QHBoxLayout()
  for title,action in [('Refresh Stats',lambda:self.refresh(True)),('Pool Payouts',self.open_pool),('1-thread Offline Test',self.benchmark)]:
   b=QPushButton(title);b.clicked.connect(action);row.addWidget(b)
  layout.addLayout(row)
  self.notice=QLabel();self.notice.setWordWrap(True);layout.addWidget(self.notice)
  explanation=QLabel('Accepted shares are work the pool accepted, not payments. The unpaid pool balance is your confirmed reward balance; the pool sends payouts to your receive address when its threshold and payout settings allow. RandomX mining is converted by unMineable into your chosen currency.');explanation.setWordWrap(True);layout.addWidget(explanation)
  layout.addStretch();scroll=QScrollArea();scroll.setWidgetResizable(True);scroll.setFrameShape(QScrollArea.Shape.NoFrame);scroll.setWidget(page);self.tabs.addTab(scroll,'Mining Stats')
  self.log=QPlainTextEdit();self.log.setReadOnly(True);self.log.document().setMaximumBlockCount(1200);self.tabs.addTab(self.log,'Engine Log')
  menu=self.menuBar().addMenu('Idle Miner');self.populate(menu)
  self.tray=QSystemTrayIcon(QIcon(str(ROOT/'icon.png')),self);self.tray_menu=QMenu()
  self.summary=QLabel('Stopped');self.summary.setWordWrap(True);self.summary.setContentsMargins(14,10,14,10);self.summary.setMinimumWidth(320)
  summary_action=QWidgetAction(self.tray_menu);summary_action.setDefaultWidget(self.summary);self.tray_menu.addAction(summary_action);self.tray_menu.addSeparator();self.populate(self.tray_menu)
  self.tray.setContextMenu(self.tray_menu);self.tray.activated.connect(lambda reason:self.showNormal() if reason==QSystemTrayIcon.ActivationReason.Trigger else None)
  self.last_color=None;self.apply_visibility()
  self.timer=QTimer(self);self.timer.timeout.connect(self.tick);self.timer.start(1000);self.tick()
 def populate(self,menu):
  for title,fn in [('Mining Stats',self.show_stats),('Start Mining',self.start),('Stop Mining',self.stop)]:menu.addAction(title,fn)
  boost=menu.addMenu('Boost Mining')
  for minutes in DURATIONS:boost.addAction(f'{minutes} Min' if minutes<60 else f'{minutes//60} Hour'+('s' if minutes>60 else ''),lambda m=minutes:self.boost(m))
  menu.addAction('End Boost · Return to Automatic',self.end_boost);menu.addAction('Settings…',self.settings_dialog)
  login=menu.addAction('Start at Login');login.setCheckable(True);login.setChecked(AUTOSTART.exists());login.triggered.connect(self.set_login)
  menu.aboutToShow.connect(lambda:login.setChecked(AUTOSTART.exists()))
  currencies=menu.addMenu('Switch Currency')
  another=menu.addMenu('Open Another Currency')
  for coin in COINS:
   currencies.addAction(coin,lambda c=coin:self.switch_currency(c))
   another.addAction(coin,lambda c=coin:self.open_currency(c))
  menu.addAction('About Idle Miner',self.about);menu.addSeparator();menu.addAction('Quit Idle Miner',self.quit)
 def show_stats(self):self.tabs.setCurrentIndex(0);self.showNormal();self.raise_();self.activateWindow()
 def start(self):
  if self.enabled or self.proc is not None:return
  if not valid_wallet(self.settings['address'],self.settings['coin']):self.settings_dialog();return
  self.work=Work();self.graph.work=self.work;self.clock.start();self.enabled=True;self.fatal='';self.sensors.ceiling=12;self.tick()
 def stop(self,*_,preserve_switch_resume=False):
  if not preserve_switch_resume:self.pending_resume=False
  self.enabled=False;self.clock.stop();self.boost_until=0;self.benchmark_until=0;self.fatal='';self.stop_engine();self.tick()
 def boost_menu(self):self.choose_boost()
 def choose_boost(self):
  menu=QMenu(self)
  for m in DURATIONS:menu.addAction(f'{m} Min' if m<60 else f'{m//60} Hour'+('s' if m>60 else ''),lambda minutes=m:self.boost(minutes))
  menu.exec(self.mapToGlobal(self.rect().center()))
 def boost(self,minutes):
  if self.benchmark_until:QMessageBox.information(self,'Benchmark running','Stop the offline test before starting a boost.');return
  if not valid_wallet(self.settings['address'],self.settings['coin']):self.settings_dialog();return
  if not self.enabled:self.start()
  self.boost_until=now()+minutes*60;self.sensors.ceiling=12;self.tick()
 def end_boost(self):self.boost_until=0;self.tick()
 def benchmark(self):
  if self.proc is not None or self.enabled:QMessageBox.information(self,'Stop mining first','Stop the current session before running the offline test.');return
  self.fatal='';self.work=Work();self.graph.work=self.work;self.clock.start();self.benchmark_until=now()+70;self.tick()
 def start_engine(self,n,benchmark):
  try:
   if n>self.coordinator.data['reserved']:raise ValueError('The shared CPU reservation is not ready.')
   data=config(self.settings,n,benchmark)
   fd=os.open(self.configpath,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
   with os.fdopen(fd,'w') as f:json.dump(data,f)
   logs=self.profile_state/'logs';logs.mkdir(exist_ok=True,mode=0o700)
   for f in sorted(logs.glob('*.log'))[:-9]:f.unlink()
   self.logpath=logs/(str(int(now()))+'-'+uuid.uuid4().hex[:6]+'.log');self.logfile=self.logpath.open('w')
   self.log.clear();self.buffer='';self.work.engine_started(benchmark);self.current_threads=n;self.stopping=False
   p=QProcess(self);self.proc=p;p.setProcessChannelMode(QProcess.ProcessChannelMode.MergedChannels)
   p.setProgram(str(ROOT/'miner-supervisor'));args=[str(os.getpid()),'--lease='+str(self.coordinator.engine_lock),str(ROOT/'xmrig'),'-c',str(self.configpath),'--no-color']
   self.engine_ready=False;self.change_deadline=0;self.engine_offline=benchmark
   p.setArguments(args);p.readyReadStandardOutput.connect(self.read_engine);p.finished.connect(self.engine_done);p.errorOccurred.connect(self.engine_error);p.start()
  except Exception as e:
   self.enabled=False;self.clock.stop();self.benchmark_until=0;self.fatal=str(e);self.cleanup_engine()
 def read_engine(self):
  if self.proc is None:return
  text=bytes(self.proc.readAllStandardOutput()).decode(errors='replace');self.buffer+=text
  while '\n' in self.buffer:
   line,self.buffer=self.buffer.split('\n',1)
   if 'READY threads ' in line:
    if f'READY threads {self.current_threads}/{self.current_threads} ' in line:self.engine_ready=True;self.change_deadline=0;self.coordinator.reserve(self.current_threads)
    else:self.fatal='Engine reported an unexpected thread count; stopped for safety.';self.enabled=False;self.clock.stop();self.benchmark_until=0;self.stop_engine()
   self.work.consume(line);self.log.appendPlainText(line)
   if self.logfile and self.logfile.tell()<2_000_000:self.logfile.write(line+'\n');self.logfile.flush()
  if len(self.buffer)>65536:self.buffer=''
 def change_threads(self,n):
  if not self.engine_ready or self.change_deadline or self.stopping:return
  if n>self.current_threads and self.coordinator.update(self.settings['coin'],n,self.settings['idle_threads'],os.cpu_count() or 1)<n:return
  try:
   temp=self.configpath.with_suffix('.tmp');temp.write_text(json.dumps(config(self.settings,n,self.engine_offline)));temp.chmod(0o600);temp.replace(self.configpath)
   self.current_threads=n;self.engine_ready=False;self.change_deadline=now()+15;self.work.threads_changed()
  except Exception as e:self.fatal=str(e);self.enabled=False;self.clock.stop();self.boost_until=0;self.benchmark_until=0;self.stop_engine()
 def stop_engine(self):
  if self.proc and not self.stopping:self.stopping=True;self.proc.terminate()
 def engine_error(self,error):
  if error==QProcess.ProcessError.FailedToStart:
   self.fatal='Could not start the mining engine. Reinstall or check Engine Log.';self.enabled=False;self.clock.stop();self.benchmark_until=0;self.cleanup_engine()
 def engine_done(self,code,status):
  self.read_engine()
  if not self.stopping and not (self.benchmark_until and code==0):
   self.fatal=f'Engine exited ({code}). Check Engine Log before restarting.';self.enabled=False;self.clock.stop();self.boost_until=0
  if not self.stopping:self.benchmark_until=0
  if not self.enabled and not self.benchmark_until:self.clock.stop()
  self.cleanup_engine()
 def cleanup_engine(self):
  if self.logfile:self.logfile.close();self.logfile=None
  if self.proc:self.proc.deleteLater();self.proc=None
  self.coordinator.reserve(0);self.stopping=False;self.current_threads=0;self.engine_ready=False;self.change_deadline=0;self.work.rate=None
  self.configpath.unlink(missing_ok=True)
 def tick(self):
  t=now()
  self.refresh_settings()
  if self.coordinator.take_focus():self.show_stats()
  self.clock.sample(bool(self.proc and self.engine_ready and not self.stopping and self.work.rate and t-self.work.updated<=30),t)
  if self.pending_coin and self.proc is None:self.finish_switch()
  if t-self.last_tick>10:self.resume_until=t+10;self.stop_engine()
  self.last_tick=t
  if self.boost_until and t>=self.boost_until:self.boost_until=0
  if self.benchmark_until and t>=self.benchmark_until:self.benchmark_until=0;self.clock.stop();self.stop_engine()
  if self.change_deadline and t>=self.change_deadline:
   self.fatal='Thread change was not confirmed; mining stopped. See Engine Log.';self.enabled=False;self.clock.stop();self.boost_until=0;self.benchmark_until=0;self.stop_engine()
  e=self.sensors.sample(self.current_threads if self.engine_ready and not self.stopping else 0)
  desired=threads(self.settings,e,self.boost_until>t,self.sensors.ceiling) if self.enabled else 0
  if self.benchmark_until:
   desired=1 if e.on_ac and not e.hot and not e.memory_low else 0
   if not desired:self.benchmark_until=0;self.clock.stop()
  startup_memory=desired>0 and self.proc is None and self.sensors.available_bytes<3*1024**3
  if startup_memory:desired=0
  if t<self.resume_until:desired=0
  requested=desired
  desired=self.coordinator.update(self.settings['coin'],desired,self.settings['idle_threads'],e.cores)
  if not desired and self.proc is None:self.coordinator.reserve(0)
  self.desired=desired
  if self.proc and not self.stopping and desired!=self.current_threads:
   if desired==0 or (not self.engine_ready and not self.change_deadline and desired<self.current_threads):self.stop_engine()
   elif self.engine_ready:self.change_threads(desired)
  if desired and self.proc is None:self.start_engine(desired,bool(self.benchmark_until))
  if self.fatal:state='Stopped · issue'
  elif startup_memory:state='Paused · 3 GB free memory needed to start RandomX'
  elif self.benchmark_until:state=f'Offline benchmark · {max(0,int(self.benchmark_until-t))} seconds left'
  elif not self.enabled:state='Stopping…' if self.proc else 'Stopped'
  elif not desired:
   reason='shared CPU budget or another miner for this currency' if requested else 'battery' if not e.on_ac else 'temperature' if e.hot else 'memory pressure' if e.memory_low else 'resuming from sleep' if t<self.resume_until else '3 GB free memory needed to start RandomX' if startup_memory else 'waiting for five minutes idle'
   state='Paused · '+reason
  else:
   state=('Boost mining' if self.boost_until else 'Mining while idle' if e.idle and e.idle_known else 'Mining lightly')+f' · {desired} thread'+('s' if desired!=1 else '')
   if self.boost_until:
    remaining=int(self.boost_until-t);state+=f' · {remaining//3600}:{remaining//60%60:02}:{remaining%60:02} left'
  color,message=self.work.health(bool(desired),self.proc is not None,self.stopping or bool(self.change_deadline),self.fatal,'' if self.benchmark_until else self.net_error)
  if color!=self.last_color:
   pix=QPixmap(40,40);pix.fill(Qt.GlobalColor.transparent);p=QPainter(pix);p.setRenderHint(QPainter.RenderHint.Antialiasing);p.setPen(QColor({'green':'#25a65a','red':'#e04444','gray':'#8b8b8b'}[color]));p.setFont(QFont('sans',27,QFont.Weight.Bold));p.drawText(pix.rect(),Qt.AlignmentFlag.AlignCenter,'₿');p.end();self.tray.setIcon(QIcon(pix));self.last_color=color
  self.state_label.setText(state);self.health.setText(message);self.tray.setToolTip('Idle Miner · '+state+'\n'+message)
  rate=f'{self.work.rate:.1f} H/s' if self.proc and self.work.rate is not None and t-self.work.updated<=30 else 'Awaiting a fresh sample' if self.proc else '—'
  self.rate.setText('RandomX: '+rate+' → '+self.settings['coin']);self.shares.setText(f'Accepted shares this session: {self.work.accepted} · Rejected: {self.work.rejected}')
  self.timing.setText(('Session started: '+QLocale.system().toString(QDateTime.fromMSecsSinceEpoch(int(self.clock.wall*1000)),QLocale.FormatType.ShortFormat) if self.clock.wall is not None else 'Session: not started')+'\nSession runtime: '+duration(self.clock.elapsed())+' · Hashing: '+duration(self.clock.hashing)+' · App uptime: '+duration(self.clock.uptime()))
  self.render_money();self.summary.setText(state+'\n'+message+'\n'+self.rate.text()+'\n'+self.money.text().split('\n')[0])
  notices=[]
  if not e.idle_known:notices.append('Idle detection is awaiting confirmation; automatic mode stays light. KDE confirms after its first idle event.')
  if self.sensors.virtual:notices.append('Virtual machine: host battery, temperature and activity are not visible. Keep the host plugged in; this VM follows guest activity.')
  elif not self.sensors.temps:notices.append('Temperature sensors unavailable; keep an eye on system temperature.')
  if self.sensors.ceiling<12:notices.append(f'High CPU load reduced this session to at most {self.sensors.ceiling} threads. A new Start or Boost resets that limit.')
  if not QSystemTrayIcon.isSystemTrayAvailable():
   if not self.isVisible():self.showNormal()
   notices.append('This desktop has no tray support. Use this window; closing it stops mining.')
  self.notice.setText('\n'.join(notices));self.graph.update();self.refresh()
 def refresh(self,force=False):
  if self.offline_test or self.net_busy or now()-self.last_fetch<(30 if force else 120):return
  self.net_busy=True;self.last_fetch=now();self.net_key=uuid.uuid4().hex;self.network.fetch(self.net_key,self.settings.copy())
 def network_result(self,r):
  if r['key']!=self.net_key:return
  self.net_busy=False;self.net_error=' '.join(r['errors'])
  if r['price'] is not None:self.quote=r['price'];self.quote_at=now()
  if r['pool'] is not None:
   self.pool=r['pool'];self.pool_at=now()
   if self.pool['issue']:self.net_error+=' Provider reports a payout issue; check Pool Payouts.'
  self.render_money()
 def render_money(self):
  coin=self.settings['coin'];lines=[]
  lines.append(f'1 {coin} ≈ ${self.quote:,.2f} USD'+(' · last known' if now()-self.quote_at>600 or self.net_error else '') if self.quote is not None else f'{coin} price: awaiting confirmation')
  if self.pool:
   p=self.pool;stale=now()-self.pool_at>600 or bool(self.net_error)
   lines.append(('Last known unpaid balance' if stale else 'Unpaid pool balance')+f": {p['balance']:.8f} {coin}")
   if self.quote is not None and now()-self.quote_at<=600:
    amount=p['balance']*self.quote;lines.append('Approximate value: '+('<$0.01' if 0<amount<.01 else f'${amount:,.2f}')+' USD')
   if p['rewards'] is not None:lines.append(f"Pool rewards, past 24 hours: {p['rewards']:.8f} {coin}")
   lines.append(f"Paid by pool: {p['paid']:.8f} {coin}")
   lines.append(f"Payout minimum: {p['payment_threshold']:.8f} {coin} · {min(100,100*p['payable']/p['payment_threshold']):.2f}% payable")
   lines.append('Automatic payouts: '+('on' if p['auto'] is True else 'off' if p['auto'] is False else 'not reported'))
   lines.append(f'Pool checked {int(max(0,now()-self.pool_at))} seconds ago · refreshes every 2 minutes')
  else:lines.append('Pool earnings: awaiting confirmation' if self.settings['pool_stats'] else 'Pool earnings: disabled in Settings')
  if self.net_error:lines.append(self.net_error)
  self.money.setText('\n'.join(lines))
 def apply_visibility(self):
  tray_available=QSystemTrayIcon.isSystemTrayAvailable()
  self.tray.setVisible(self.settings['show_menu_bar'] and tray_available)
  if self.settings['show_dock'] or not tray_available:self.showNormal()
  else:self.hide()
 def refresh_settings(self):
  try:latest=self.store.load()
  except Exception:return
  coin=self.settings['coin'];latest['coin']=coin;latest['address']=latest['wallets'][coin]
  if latest==self.settings:return
  address_changed=latest['address']!=self.settings['address']
  visibility_changed=any(latest[k]!=self.settings[k] for k in ('show_dock','show_menu_bar'))
  self.settings=latest
  if address_changed:
   self.stop();self.fatal='The active receive address changed in Settings. Start a new session to use it.'
   self.reset_reporting()
  if visibility_changed:self.apply_visibility()
 def reset_reporting(self):
  self.quote=self.pool=None;self.net_error='';self.net_key=uuid.uuid4().hex;self.net_busy=False;self.last_fetch=-1000
 def switch_currency(self,coin):
  if coin==self.settings['coin'] and self.pending_coin is None:return
  self.pending_coin=coin;self.pending_resume=self.enabled or self.pending_resume;self.stop(preserve_switch_resume=True)
  if self.proc is None:self.finish_switch()
 def finish_switch(self):
  if self.pending_coin is None:return
  coin=self.pending_coin;resume=self.pending_resume;self.pending_coin=None;self.pending_resume=False
  self.settings['coin']=coin;self.settings['address']=self.settings['wallets'][coin]
  if self.profile=='default':
   baseline=self.store.load();edited=validated(baseline);edited['coin']=coin
   self.store.save(edited,baseline)
  self.work=Work();self.graph.work=self.work;launched=self.clock.launched;self.clock=SessionClock();self.clock.launched=launched;self.reset_reporting();self.setWindowTitle('Idle Miner · '+coin)
  if resume and valid_wallet(self.settings['address'],coin):self.start()
  elif resume:QTimer.singleShot(0,self.settings_dialog)
 def open_currency(self,coin):
  if coin==self.settings['coin']:self.show_stats();return
  subprocess.Popen([sys.executable,str(ROOT/'app.py'),'--profile='+coin]+(['--offline-ui-test'] if self.offline_test else []),start_new_session=True)
 def settings_dialog(self):
  self.refresh_settings();baseline=validated(self.settings)
  dialog=QDialog(self);dialog.setWindowTitle('Idle Miner Settings');dialog.setMinimumWidth(540);form=QFormLayout(dialog)
  wallets={}
  for coin in COINS:
   field=QLineEdit(baseline['wallets'][coin]);field.setPlaceholderText('Public native-network receive address');wallets[coin]=field;form.addRow(coin+' receive address',field)
  count=QComboBox();count.addItems(['2','4','8','12']);count.setCurrentText(str(self.settings['idle_threads']))
  pause=QCheckBox('Pause completely while I am using this computer');pause.setChecked(self.settings['pause_active'])
  stats=QCheckBox('Read earnings from unMineable using my public receive address');stats.setChecked(self.settings['pool_stats'])
  dock=QCheckBox('Show window / taskbar');dock.setChecked(self.settings['show_dock'])
  tray=QCheckBox('Show tray / menu bar');tray.setChecked(self.settings['show_menu_bar'])
  login=QCheckBox('Start at Login');login.setChecked(AUTOSTART.exists());login.clicked.connect(self.set_login)
  for label,widget in [('Shared maximum idle / boost threads',count),('',pause),('',stats),('',dock),('',tray),('',login)]:form.addRow(label,widget)
  note=QLabel('Save each currency’s public Receive address on its native network. No password, seed phrase or private key is needed.\n\nUse Switch Currency or Open Another Currency from the menu. All running currencies share this thread budget and reserve two CPU cores where possible. Each needs about 3 GB free memory to start.\n\nKeep at least one visibility option selected. Desktops without a usable tray always keep a window visible. Start at Login opens stopped; that checkbox takes effect immediately. Saving settings stops this session.');note.setWordWrap(True);form.addRow(note)
  error=QLabel();error.setWordWrap(True);form.addRow(error)
  buttons=QDialogButtonBox(QDialogButtonBox.StandardButton.Save|QDialogButtonBox.StandardButton.Cancel);form.addRow(buttons);buttons.rejected.connect(dialog.reject)
  def save():
   try:
    edited={**baseline,'wallets':{coin:field.text().strip() for coin,field in wallets.items()},'idle_threads':int(count.currentText()),'pause_active':pause.isChecked(),'pool_stats':stats.isChecked(),'show_dock':dock.isChecked(),'show_menu_bar':tray.isChecked()}
    s=self.store.save(edited,baseline);s['coin']=self.settings['coin'];s['address']=s['wallets'][s['coin']]
    self.stop();self.settings=s;self.reset_reporting();self.apply_visibility();dialog.accept();self.tick()
   except Exception as e:error.setText(str(e))
  buttons.accepted.connect(save);dialog.exec()
 def set_login(self,enabled):
  try:
   if enabled:
    AUTOSTART.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(Path.home()/'.local/share/applications/idle-miner.desktop',AUTOSTART)
   else:AUTOSTART.unlink(missing_ok=True)
  except OSError as e:QMessageBox.warning(self,'Login setting could not be saved',str(e))
 def open_pool(self):
  if valid_wallet(self.settings['address'],self.settings['coin']):QDesktopServices.openUrl(QUrl(f"https://unmineable.com/coins/{self.settings['coin']}/address/{self.settings['address']}"))
  else:self.settings_dialog()
 def about(self):
  dialog=QDialog(self);dialog.setWindowTitle('About Idle Miner');layout=QVBoxLayout(dialog)
  icon=QLabel();icon.setPixmap(QPixmap(str(ROOT/'icon.png')).scaled(96,96,Qt.AspectRatioMode.KeepAspectRatio,Qt.TransformationMode.SmoothTransformation));icon.setAlignment(Qt.AlignmentFlag.AlignCenter);layout.addWidget(icon)
  for text in ('Idle Miner','By Jeffry Zander',f'Version {VERSION} ({BUILD}) · Linux · Fedora / Asahi / Ubuntu','RandomX CPU mining · unMineable payouts','XMRig 6.26.0 · 1% developer donation','GPL-3.0 · source and licenses included'):
   label=QLabel(text);label.setAlignment(Qt.AlignmentFlag.AlignCenter);layout.addWidget(label)
  dialog.exec()
 def closeEvent(self,event):
  if QSystemTrayIcon.isSystemTrayAvailable() and self.tray.isVisible() and not self.quitting:self.hide();event.ignore()
  else:self.quit();event.accept()
 def quit(self):
  if self.quitting:return
  self.quitting=True;self.timer.stop();self.enabled=False;self.stop_engine()
  if self.proc:
   if not self.proc.waitForFinished(5500):
    # Never kill the supervisor before it has reaped the engine.
    self.quitting=False;self.timer.start();QMessageBox.warning(self,'Engine is still stopping','Please wait a moment, then try Quit again.');return
  self.clock.stop();self.coordinator.close();self.sensors.close();QApplication.instance().quit()

def main():
 os.umask(0o077);STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
 try:coordinator=Coordinator(STATE,PROFILE)
 except BlockingIOError:
  atomic(STATE/(PROFILE+'.focus.json'),{'time':time.time()});return
 except ValueError as e:raise SystemExit(str(e))
 app=QApplication(sys.argv);app.setApplicationName('Idle Miner');app.setDesktopFileName('idle-miner');app.setQuitOnLastWindowClosed(False)
 w=Window('--offline-ui-test' in sys.argv,coordinator=coordinator);w.apply_visibility()
 signal.signal(signal.SIGTERM,lambda *a:w.quit());signal.signal(signal.SIGINT,lambda *a:w.quit())
 if '--offline-ui-test' in sys.argv:
  def capture():w.grab().save('/tmp/idle-miner-linux.png');print('PASS: Linux UI launched stopped',flush=True);w.quit()
  QTimer.singleShot(2000,capture)
 app.exec()
if __name__=='__main__':main()
