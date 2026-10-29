#!/usr/bin/env python3
"""Idle Miner for Linux. A user session app; never a privileged mining service."""
import os,sys,json,signal,fcntl,shutil,uuid,time,subprocess,threading,tempfile
from pathlib import Path
from PySide6.QtCore import Qt,QTimer,QProcess,QUrl,QPointF,QDateTime,QLocale,QObject,Signal
from PySide6.QtGui import QIcon,QPixmap,QPainter,QPen,QColor,QFont,QDesktopServices,QAction
from PySide6.QtWidgets import (QApplication,QMainWindow,QWidget,QVBoxLayout,QHBoxLayout,QLabel,QPushButton,QToolButton,QMenu,QSystemTrayIcon,QDialog,QFormLayout,QLineEdit,QComboBox,QCheckBox,QDialogButtonBox,QMessageBox,QPlainTextEdit,QTabWidget,QWidgetAction,QScrollArea)
from core import VERSION,BUILD,DEFAULTS,COINS,DURATIONS,Work,SessionClock,duration,now,validated,valid_wallet,threads,config
from coordination import SettingsStore,Coordinator,atomic
from startup import startup_plan,autostart_enabled,login_entry,save_login_preference
from platform_linux import Sensors
from network import Network
from shared_tray import SharedTray,profile_currency,focus_matches
from updates import AutomaticUpdates,check_async,newer,install_metadata,prepare_update,UpdateCancelled,request_shutdown,begin_resume,acknowledge_resume,consume_resume,discard_resume,installed_version
ROOT=Path(__file__).resolve().parent
STATE=Path(os.environ.get('IDLE_MINER_STATE',str(Path.home()/'.config/idle-miner')))
PROFILE=next((arg.split('=',1)[1] for arg in sys.argv if arg.startswith('--profile=')),'default')
AUTOSTART=Path.home()/'.config/autostart/idle-miner.desktop'

def profile_conflict_message(coin,current):
 return f'The {coin} profile is currently showing {current}. Use Switch Currency in that window, or quit that profile, before opening {coin}.' if current else 'This currency profile is busy and has not reported its current currency. Try again in a moment.'

class UpdateBridge(QObject):
 automatic=Signal(object)
 ready=Signal(object)
 progress=Signal(str)
 prepared=Signal(object)
 failed=Signal(str)

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
  self.shared_tray=SharedTray(STATE,self.coordinator);self.currency_menus={};self.update_busy=False;self.update_last=-1000;self.quit_group=None;self.update_bridge=UpdateBridge(self);self.update_bridge.ready.connect(self.update_result);self.update_bridge.progress.connect(self.update_progress);self.update_bridge.prepared.connect(self.update_prepared);self.update_bridge.failed.connect(self.update_failed);self.update_dialog=None;self.update_preparing=False;self.update_cancel=threading.Event()
  self.tray=QSystemTrayIcon(QIcon(str(ROOT/'icon.png')),self);self.tray_menu=QMenu()
  self.summary=QLabel('Stopped');self.summary.setWordWrap(True);self.summary.setContentsMargins(14,10,14,10);self.summary.setMinimumWidth(320)
  self.tray_menu.aboutToShow.connect(self.rebuild_tray_menu);self.rebuild_tray_menu()
  self.tray.setContextMenu(self.tray_menu);self.tray.activated.connect(lambda reason:self.showNormal() if reason==QSystemTrayIcon.ActivationReason.Trigger else None)
  self.last_color=None;self.apply_visibility()
  self.automatic_updates=AutomaticUpdates(STATE);self.automatic_busy=False;self.update_bridge.automatic.connect(self.scheduled_update_result)
  self.automatic_timer=QTimer(self);self.automatic_timer.timeout.connect(self.scheduled_update_tick);self.automatic_timer.start(60000);QTimer.singleShot(0,self.scheduled_update_tick)
  self.timer=QTimer(self);self.timer.timeout.connect(self.tick);self.timer.start(1000);self.tick()
 def populate(self,menu):
  for title,fn in [('Mining Stats',self.show_stats),('Start Mining',self.start),('Stop Mining',self.stop)]:menu.addAction(title,fn)
  boost=menu.addMenu('Boost Mining')
  for minutes in DURATIONS:boost.addAction(f'{minutes} Min' if minutes<60 else f'{minutes//60} Hour'+('s' if minutes>60 else ''),lambda m=minutes:self.boost(m))
  menu.addAction('End Boost · Return to Automatic',self.end_boost);menu.addAction('Settings…',self.settings_dialog)
  login=menu.addAction('Start at Login');login.setCheckable(True);login.setChecked(autostart_enabled(AUTOSTART));login.triggered.connect(self.set_login)
  menu.aboutToShow.connect(lambda:login.setChecked(autostart_enabled(AUTOSTART)))
  currencies=menu.addMenu('Switch Currency')
  another=menu.addMenu('Open Another Currency')
  for coin in COINS:
   currencies.addAction(coin,lambda c=coin:self.switch_currency(c))
   another.addAction(coin,lambda c=coin:self.open_currency(c))
  menu.addAction('Engine Log',self.show_log);menu.addAction('Refresh Stats',lambda:self.refresh(True));menu.addAction('Pool Payouts',self.open_pool)
  update=menu.addAction('Check for Updates…',self.check_updates);menu.aboutToShow.connect(lambda:update.setText(self.update_menu_title()));menu.addAction('About Idle Miner',self.about);menu.addSeparator();menu.addAction('Quit This Currency',self.quit);menu.addAction('Quit Idle Miner',self.quit_all)
 def show_log(self):self.tabs.setCurrentIndex(1);self.showNormal();self.raise_();self.activateWindow()
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
  if self.quitting:return
  for action in self.shared_tray.take_commands(self.settings['coin']):
   if action.startswith('quit-update:'):self.quit_for_update(action.split(':',1)[1])
   elif action.startswith('boost:'):self.boost(int(action.split(':')[1]))
   else:
    handler={'show_stats':self.show_stats,'show_log':self.show_log,'start':self.start,'stop':self.stop,'end_boost':self.end_boost,'settings':self.settings_dialog,'pool':self.open_pool,'refresh':lambda:self.refresh(True),'quit':self.quit}.get(action)
    if handler:handler()
   if self.quitting:return
  self.refresh_settings()
  if self.coordinator.take_focus(self.settings['coin']):self.show_stats()
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
  self.state_label.setText(state);self.health.setText(message)
  rate=f'{self.work.rate:.1f} H/s' if self.proc and self.work.rate is not None and t-self.work.updated<=30 else 'Awaiting a fresh sample' if self.proc else '—'
  self.rate.setText('RandomX: '+rate+' → '+self.settings['coin']);self.shares.setText(f'Accepted shares this session: {self.work.accepted} · Rejected: {self.work.rejected}')
  self.timing.setText(('Session started: '+QLocale.system().toString(QDateTime.fromMSecsSinceEpoch(int(self.clock.wall*1000)),QLocale.FormatType.ShortFormat) if self.clock.wall is not None else 'Session: not started')+'\nSession runtime: '+duration(self.clock.elapsed())+' · Hashing: '+duration(self.clock.hashing)+' · App uptime: '+duration(self.clock.uptime()))
  self.render_money();self.summary.setText(state+'\n'+message+'\n'+self.rate.text()+'\n'+self.money.text().split('\n')[0])
  self.shared_tray.publish(self.settings['coin'],dict(color=color,state=state,health='Issue: check this currency window.' if self.fatal else message,rate=self.rate.text(),shares=self.shares.text(),timing=self.timing.text(),money=self.money.text()))
  self.update_shared_tray()
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
 def status_icon(self,color,glyph='●'):
  pix=QPixmap(40,40);pix.fill(Qt.GlobalColor.transparent);p=QPainter(pix);p.setRenderHint(QPainter.RenderHint.Antialiasing);p.setPen(QColor({'green':'#25a65a','red':'#e04444','gray':'#8b8b8b'}[color]));p.setFont(QFont('sans',27,QFont.Weight.Bold));p.drawText(pix.rect(),Qt.AlignmentFlag.AlignCenter,glyph);p.end();return QIcon(pix)
 def update_shared_tray(self):
  owner=self.shared_tray.elect();available=QSystemTrayIcon.isSystemTrayAvailable()
  self.tray.setVisible(owner and available and self.settings['show_menu_bar'])
  snapshots=self.shared_tray.snapshots()
  colors=[row['color'] for row in snapshots.values()]
  color='red' if 'red' in colors else 'green' if 'green' in colors else 'gray'
  if color!=self.last_color:self.tray.setIcon(self.status_icon(color,'₿'));self.last_color=color
  self.tray.setToolTip('Idle Miner · '+str(len(snapshots))+' currencies running')
  for coin,menu in self.currency_menus.items():
   row=snapshots.get(coin);menu.setIcon(self.status_icon(row['color'] if row else 'gray'))
 def rebuild_tray_menu(self):
  self.tray_menu.clear();self.currency_menus={};rows=self.shared_tray.snapshots()
  title=self.tray_menu.addAction('Idle Miner');title.setEnabled(False);self.tray_menu.addSeparator()
  for coin in COINS:
   if coin not in rows and not valid_wallet(self.settings['wallets'][coin],coin):continue
   menu=self.tray_menu.addMenu(coin);self.currency_menus[coin]=menu
   menu.aboutToShow.connect(lambda c=coin,m=menu:self.populate_currency(m,c))
   menu.setIcon(self.status_icon(rows[coin]['color'] if coin in rows else 'gray'));self.populate_currency(menu,coin)
  self.tray_menu.addSeparator();self.tray_menu.addAction('Settings…',self.settings_dialog)
  self.tray_menu.addAction(self.update_menu_title(),self.check_updates);self.tray_menu.addAction('About Idle Miner',self.about)
  self.tray_menu.addSeparator();self.tray_menu.addAction('Quit Idle Miner',self.quit_all)
 def populate_currency(self,menu,coin):
  menu.clear();row=self.shared_tray.snapshots().get(coin)
  if row is None:
   status=menu.addAction('Not running');status.setEnabled(False)
   menu.addAction('Open '+coin+' · Stopped',lambda:self.open_currency(coin));return
  for key in ('state','health','rate','shares','timing','money'):
   for line in row[key].splitlines():
    if line:action=menu.addAction(line);action.setEnabled(False)
  menu.addSeparator()
  for label,command in [('Mining Stats','show_stats'),('Start Mining','start'),('Stop Mining','stop')]:
   action=menu.addAction(label,lambda c=coin,a=command:self.dispatch_currency(c,a));action.setEnabled(row['fresh'])
  boost=menu.addMenu('Boost Mining');boost.setEnabled(row['fresh'])
  for minutes in DURATIONS:boost.addAction(f'{minutes} Min' if minutes<60 else f'{minutes//60} Hour'+('s' if minutes>60 else ''),lambda c=coin,m=minutes:self.dispatch_currency(c,'boost:'+str(m)))
  for label,command in [('End Boost · Return to Automatic','end_boost'),('Settings…','settings'),('Pool Payouts','pool'),('Refresh Stats','refresh'),('Engine Log','show_log'),('Quit This Currency','quit')]:
   action=menu.addAction(label,lambda c=coin,a=command:self.dispatch_currency(c,a));action.setEnabled(row['fresh'])
 def dispatch_currency(self,coin,action):
  row=self.shared_tray.snapshots().get(coin)
  if row and row['fresh']:
   if not self.shared_tray.send(row,action):QMessageBox.warning(self,'Currency is busy','This currency could not receive the action. Try again in a moment.')
  else:QMessageBox.information(self,'Currency status unavailable','This currency is not reporting a fresh status. Open its window and try again.')
 def quit_all(self):
  if self.quit_group is not None:return
  targets=[row for row in self.shared_tray.snapshots(by_profile=True).values() if row['profile']!=self.profile]
  failed=False
  for row in targets:
   if not self.shared_tray.send(row,'quit'):failed=True
  if failed:QMessageBox.warning(self,'Some currencies are busy','A currency could not receive Quit. Wait a moment and try Quit Idle Miner again.');return
  if not targets:self.quit();return
  self.quit_group=targets;self.quit_deadline=now()+12;self.stop();self.check_quit_all()
 def check_quit_all(self):
  if self.quitting or self.quit_group is None:return
  live=self.shared_tray.snapshots(by_profile=True)
  remaining=[row for row in self.quit_group if row['profile'] in live and live[row['profile']]['pid']==row['pid'] and live[row['profile']]['nonce']==row['nonce']]
  if not remaining:self.quit_group=None;self.quit();return
  if now()>=self.quit_deadline:
   self.quit_group=None;self.show_stats();QMessageBox.warning(self,'A currency is still stopping','Wait for the remaining currency to stop, then try Quit Idle Miner again.');return
  QTimer.singleShot(250,self.check_quit_all)
 def update_menu_title(self):
  release=self.automatic_updates.available(VERSION,BUILD) if hasattr(self,'automatic_updates') else None
  return f"Update Available: {release['version']} ({release['build']})…" if release else 'Check for Updates…'
 def scheduled_update_tick(self):
  if self.quitting or self.automatic_busy or self.update_busy or self.update_preparing:return
  try:
   if not self.store.load()['automatic_update_checks']:return
  except Exception:return
  self.automatic_busy=True
  def discover():
   result=self.automatic_updates.run_once(VERSION,BUILD)
   self.update_bridge.automatic.emit(result)
  threading.Thread(target=discover,daemon=True).start()
 def scheduled_update_result(self,result):
  self.automatic_busy=False
  if self.quitting or not result:return
  try:
   if not self.store.load()['automatic_update_checks']:return
  except Exception:return
  if result['notify']:self.notify_available_update(result['release'])
 def notify_available_update(self,release):
  title='Idle Miner Update Available';message=f"Idle Miner {release['version']} ({release['build']}) is available. Choose Check for Updates to review and install."
  if self.tray.isVisible() and QSystemTrayIcon.supportsMessages():
   self.tray.showMessage(title,message,QSystemTrayIcon.MessageIcon.Information,10000);return
  # Desktops without supported tray notifications retain the available-update
  # hint in the app and tray menus; discovery never opens or activates a window.
 def automatic_update_controls(self,parent):
  widget=QWidget(parent);layout=QVBoxLayout(widget);layout.setContentsMargins(0,6,0,0);layout.setSpacing(4)
  row=QHBoxLayout();check=QCheckBox('Automatically check for updates');check.setObjectName('automaticUpdateChecks');frequency=QComboBox();frequency.setObjectName('automaticUpdateFrequency');frequency.addItem('Daily','daily');frequency.addItem('Weekly','weekly');row.addWidget(check);row.addStretch();row.addWidget(frequency);layout.addLayout(row)
  hint=QLabel('Checks only while Idle Miner is running. New updates notify you; downloading and installing are always your choice.');hint.setWordWrap(True);layout.addWidget(hint)
  error=QLabel();error.setWordWrap(True);error.hide();layout.addWidget(error)
  def save(key,value):
   try:
    baseline=self.store.load();saved=self.store.save({**baseline,key:value},baseline)
    for name in ('automatic_update_checks','update_check_frequency'):self.settings[name]=saved[name]
    error.hide();self.sync_automatic_controls(widget);self.scheduled_update_tick()
   except Exception as exc:error.setText(str(exc));error.show();self.sync_automatic_controls(widget)
  check.clicked.connect(lambda enabled:save('automatic_update_checks',enabled));frequency.currentIndexChanged.connect(lambda _:save('update_check_frequency',frequency.currentData()))
  timer=QTimer(widget);timer.timeout.connect(lambda:self.sync_automatic_controls(widget));timer.start(1000);self.sync_automatic_controls(widget)
  return widget
 def sync_automatic_controls(self,parent):
  try:settings=self.store.load()
  except Exception:return
  check=parent.findChild(QCheckBox,'automaticUpdateChecks');frequency=parent.findChild(QComboBox,'automaticUpdateFrequency')
  if not check or not frequency:return
  check.blockSignals(True);frequency.blockSignals(True);check.setChecked(settings['automatic_update_checks']);frequency.setCurrentIndex(frequency.findData(settings['update_check_frequency']));frequency.setEnabled(settings['automatic_update_checks']);check.blockSignals(False);frequency.blockSignals(False)
 def check_updates(self):
  if self.update_preparing:
   if self.update_dialog:self.update_dialog.show();self.update_dialog.raise_()
   return
  if self.update_busy:QMessageBox.information(self,'Checking for updates','An update check is already in progress.');return
  if self.update_dialog and self.update_dialog.isVisible():self.update_dialog.raise_();return
  if now()-self.update_last<30:QMessageBox.information(self,'Check for Updates','Please wait a moment before checking again.');return
  self.update_cancel=threading.Event();self.update_release=None
  dialog=QDialog(self);dialog.setWindowTitle('Check for Updates');dialog.setMinimumWidth(520);layout=QVBoxLayout(dialog);layout.setContentsMargins(20,18,20,16);layout.setSpacing(10)
  header=QHBoxLayout();brand=QLabel();brand.setObjectName('updateBrandIcon');brand.setPixmap(QIcon(str(ROOT/'icon.png')).pixmap(48,48));header.addWidget(brand);heading=QLabel('Idle Miner Updates');heading.setObjectName('updateBrandTitle');font=QFont(QApplication.font());font.setPointSize(17);font.setBold(True);heading.setFont(font);header.addWidget(heading);header.addStretch();layout.addLayout(header)
  self.update_versions=QLabel(f'Installed: Idle Miner {VERSION} ({BUILD})\nLatest: checking…');layout.addWidget(self.update_versions)
  self.update_status=QLabel('Checking for updates…');self.update_status.setTextFormat(Qt.TextFormat.PlainText);self.update_status.setWordWrap(True);layout.addWidget(self.update_status)
  self.update_notes_toggle=QToolButton();self.update_notes_toggle.setText('Release Notes');self.update_notes_toggle.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon);self.update_notes_toggle.setCheckable(True);self.update_notes_toggle.setArrowType(Qt.ArrowType.RightArrow);self.update_notes_toggle.toggled.connect(self.toggle_update_notes);layout.addWidget(self.update_notes_toggle);self.update_notes_toggle.hide()
  self.update_notes=QPlainTextEdit();self.update_notes.setReadOnly(True);layout.addWidget(self.update_notes);self.update_notes.hide()
  layout.addWidget(self.automatic_update_controls(dialog))
  row=QHBoxLayout();row.addStretch();close=QPushButton('Close');close.clicked.connect(dialog.reject);row.addWidget(close)
  self.update_install=QPushButton('Download and Install Now');self.update_install.setEnabled(False);self.update_install.hide();self.update_install.clicked.connect(self.install_update);row.addWidget(self.update_install);layout.addLayout(row)
  dialog.finished.connect(lambda _:self.update_cancel.set());self.update_dialog=dialog;dialog.adjustSize();dialog.show()
  self.update_busy=True;self.update_last=now();check_async(self.update_bridge.ready.emit)
 def toggle_update_notes(self,expanded):
  self.update_notes.setVisible(expanded)
  self.update_notes_toggle.setArrowType(Qt.ArrowType.DownArrow if expanded else Qt.ArrowType.RightArrow)
  self.update_dialog.adjustSize()
 def update_result(self,result):
  self.update_busy=False
  if self.quitting or self.update_dialog is None:return
  self.update_release=None;self.update_install.setEnabled(False);self.update_install.hide()
  self.update_notes_toggle.setChecked(False);self.update_notes_toggle.hide();self.update_notes.hide();self.update_notes.clear()
  self.update_dialog.adjustSize()
  if result['error']:
   self.update_versions.setText(f'Installed: Idle Miner {VERSION} ({BUILD})\nLatest: unavailable');self.update_status.setText(result['error']);self.update_dialog.adjustSize();return
  release=result['manifest']
  self.update_versions.setText(f"Installed: Idle Miner {VERSION} ({BUILD})\nLatest: Idle Miner {release['version']} ({release['build']})")
  self.update_notes.setPlainText(release['releaseNotesText'])
  has_notes=bool(release['releaseNotesText'].strip())
  if not newer(release['version'],release['build'],VERSION,BUILD):
   self.update_status.setText('Idle Miner is up to date.');self.update_notes_toggle.setVisible(has_notes);self.update_dialog.adjustSize();return
  try:install_metadata(release)
  except ValueError as exc:self.update_status.setText(str(exc));self.update_dialog.adjustSize();return
  self.update_release=release
  self.update_status.setText('Installs here and keeps settings and wallets. Open currencies restart in their prior enabled or stopped state.')
  self.update_install.show();self.update_install.setEnabled(True);self.update_notes_toggle.setVisible(has_notes);self.update_notes_toggle.setChecked(has_notes);self.update_dialog.adjustSize()
 def update_progress(self,text):
  if self.update_dialog:self.update_status.setText(text)
 def update_failed(self,message):
  self.update_preparing=False
  if self.quitting:return
  self.update_progress(message)
  if self.update_dialog and self.update_dialog.isVisible():
   self.update_notes_toggle.setChecked(False);self.update_notes_toggle.hide();self.update_notes.hide();self.update_install.setEnabled(bool(self.update_release));self.update_dialog.adjustSize()
 def install_update(self):
  if self.update_preparing or not self.update_release:return
  self.update_preparing=True;self.update_install.setEnabled(False);release=dict(self.update_release);cancel=self.update_cancel
  def prepare():
   workspace=Path(tempfile.mkdtemp(prefix='idle-miner-update-'))
   try:
    stage=prepare_update(release,workspace,cancel,self.update_bridge.progress.emit)
    self.update_bridge.prepared.emit(dict(stage=str(stage),workspace=str(workspace)))
   except Exception as exc:
    shutil.rmtree(workspace,ignore_errors=True);self.update_bridge.failed.emit(str(exc))
  threading.Thread(target=prepare,daemon=True).start()
 def update_prepared(self,result):
  workspace=Path(result['workspace'])
  if self.update_cancel.is_set() or self.quitting:
   shutil.rmtree(workspace,ignore_errors=True);self.update_preparing=False;return
  try:
   targets=[row for row in self.shared_tray.snapshots(by_profile=True).values() if row['profile']!=self.profile]
   # Legacy/unresponsive windows must not be silently skipped by the shared tray.
   from shared_tray import held
   known={self.profile,*(row['profile'] for row in targets)}
   for profile in ('default',*COINS):
    if profile not in known and held(STATE/('app.lock' if profile=='default' else profile+'.lock')):raise ValueError('A currency window has not reported its status. Close that window, then try installing again.')
   helper=workspace/'update-helper.py';shutil.copy2(ROOT/'updates.py',helper)
   own=dict(profile=self.profile,coin=self.settings['coin'],pid=os.getpid(),nonce=self.shared_tray.nonce)
   target_version,target_build=installed_version(result['stage'])
   token=begin_resume(STATE,ROOT,VERSION,BUILD,target_version,target_build,[own,*targets],self.profile)
   self.update_resume_token=token
   # Every process captures enabled state in its own quit hook, before Stop.
   if not self.acknowledge_update(token):raise ValueError('Could not capture this currency for the update.')
   request_shutdown(self.shared_tray,targets,token)
   # The helper requires every acknowledgement and every app/engine lease.
   subprocess.Popen([sys.executable,str(helper),'--install-prepared',result['stage'],str(ROOT),str(STATE),str(workspace),token],cwd=workspace,start_new_session=True,close_fds=True)
   self.update_preparing=False;self.stop();self.quit()
  except Exception as exc:
   discard_resume(STATE,getattr(self,'update_resume_token',None))
   shutil.rmtree(workspace,ignore_errors=True);self.update_failed('Could not begin installation. '+str(exc))
 def apply_visibility(self):
  tray_available=QSystemTrayIcon.isSystemTrayAvailable()
  self.tray.setVisible(self.settings['show_menu_bar'] and tray_available and self.shared_tray.owner)
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
 def acknowledge_update(self,token):
  return acknowledge_resume(STATE,ROOT,token,self.profile,os.getpid(),self.shared_tray.nonce,self.pending_coin or self.settings['coin'],bool(self.enabled or self.pending_resume))
 def quit_for_update(self,token):
  if self.quitting or not self.acknowledge_update(token):return
  self.stop();self.quit()
 def apply_update_resume(self,token):
  plan=consume_resume(STATE,ROOT,token,self.profile,VERSION,BUILD)
  if plan is None:return
  # Restore session currency directly; never rewrite the user's saved settings.
  coin=plan['coin'];self.settings['coin']=coin;self.settings['address']=self.settings['wallets'][coin]
  self.setWindowTitle('Idle Miner · '+coin);self.reset_reporting()
  if plan['enabled'] and valid_wallet(self.settings['address'],coin):self.start()
  for row in plan['peers']:
   subprocess.Popen([sys.executable,str(ROOT/'app.py'),'--profile='+row['profile'],'--resume-update='+token],start_new_session=True)
 def apply_startup(self,args):
  marker=next((arg.split('=',1)[1] for arg in args if arg.startswith('--resume-update=')),None)
  if '--login-startup' in args:
   discard_resume(STATE,marker)
  elif marker is not None:
   self.apply_update_resume(marker);return
  self.refresh_settings()
  selected,children=startup_plan(self.settings,self.profile,args,autostart_enabled(AUTOSTART))
  if selected is None:return
  if selected!=self.settings['coin']:self.switch_currency(selected)
  # A missing/changed wallet at login must never open Settings or start mining.
  if valid_wallet(self.settings['address'],self.settings['coin']):self.start()
  for coin in children:self.open_currency(coin,start_mining=True)
 def open_currency(self,coin,start_mining=False):
  if coin not in COINS:return
  if coin==self.settings['coin']:self.show_stats();return
  row=self.shared_tray.snapshots().get(coin)
  if row:self.dispatch_currency(coin,'show_stats');return
  current=profile_currency(STATE,coin)
  if current is not None and current!=coin:
   QMessageBox.information(self,'Currency profile is in use',profile_conflict_message(coin,current));return
  subprocess.Popen([sys.executable,str(ROOT/'app.py'),'--profile='+coin]+(['--start-mining'] if start_mining else [])+(['--offline-ui-test'] if self.offline_test else []),start_new_session=True)
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
  login=QCheckBox('Start at Login');login.setChecked(autostart_enabled(AUTOSTART))
  mine=QCheckBox('Start at Login and Start Mining configured currencies');mine.setChecked(login.isChecked() and baseline['start_mining_at_login']);mine.setEnabled(login.isChecked())
  def toggle_login(enabled):
   self.set_login(enabled);login.setChecked(autostart_enabled(AUTOSTART));mine.setEnabled(login.isChecked())
   mine.setChecked(login.isChecked() and self.store.load()['start_mining_at_login'])
  login.clicked.connect(toggle_login)
  def toggle_mining(enabled):
   self.set_login_mining(enabled);mine.setChecked(autostart_enabled(AUTOSTART) and self.store.load()['start_mining_at_login'])
  mine.clicked.connect(toggle_mining)
  for label,widget in [('Shared maximum idle / boost threads',count),('',pause),('',stats),('',dock),('',tray),('',login),('',mine)]:form.addRow(label,widget)
  form.addRow(self.automatic_update_controls(dialog))
  note=QLabel('Save each currency’s public Receive address on its native network. ETH payouts use Ethereum (ETH); choose that same network in your wallet and at unMineable. A 0x address alone cannot identify its network. No password, seed phrase or private key is needed.\n\nUse Switch Currency or Open Another Currency from the menu. All running currencies share this thread budget and reserve two CPU cores where possible. Each needs about 3 GB free memory to start.\n\nKeep at least one visibility option selected. Desktops without a usable tray always keep a window visible. Start at Login opens stopped unless you also opt in to start mining every currency with a valid saved wallet. Both login checkboxes take effect immediately. Manual launches open stopped. Saving settings stops this session.');note.setWordWrap(True);form.addRow(note)
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
    AUTOSTART.parent.mkdir(parents=True,exist_ok=True);AUTOSTART.write_text(login_entry((Path.home()/'.local/share/applications/idle-miner.desktop').read_text()))
   else:
    AUTOSTART.unlink(missing_ok=True);save_login_preference(self.store,False)
   self.refresh_settings()
  except Exception as e:QMessageBox.warning(self,'Login setting could not be saved',str(e))
 def set_login_mining(self,enabled):
  try:
   save_login_preference(self.store,bool(enabled) and autostart_enabled(AUTOSTART));self.refresh_settings()
  except Exception as e:QMessageBox.warning(self,'Login setting could not be saved',str(e))
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
  if QSystemTrayIcon.isSystemTrayAvailable() and self.settings['show_menu_bar'] and self.shared_tray.owner_available() and not self.quitting:self.hide();event.ignore()
  else:self.quit();event.accept()
 def quit(self):
  if self.quitting:return
  if self.update_preparing:
   self.update_cancel.set();self.update_progress('Cancelling update preparation before quitting…');QTimer.singleShot(250,self.quit);return
  self.quitting=True;self.timer.stop();self.enabled=False;self.stop_engine()
  if self.proc:
   if not self.proc.waitForFinished(5500):
    # Never kill the supervisor before it has reaped the engine.
    self.quitting=False;self.timer.start();QMessageBox.warning(self,'Engine is still stopping','Please wait a moment, then try Quit again.');return
  self.clock.stop();self.tray.hide();self.shared_tray.close();self.coordinator.close();self.sensors.close();QApplication.instance().quit()

def main():
 os.umask(0o077);STATE.mkdir(parents=True,exist_ok=True,mode=0o700)
 try:coordinator=Coordinator(STATE,PROFILE)
 except BlockingIOError:
  if PROFILE in COINS and not focus_matches(STATE,PROFILE,PROFILE):
   duplicate_app=QApplication(sys.argv);QMessageBox.information(None,'Currency profile is in use',profile_conflict_message(PROFILE,profile_currency(STATE,PROFILE)));return
  data={'time':time.time()}
  if PROFILE in COINS:data['coin']=PROFILE
  atomic(STATE/(PROFILE+'.focus.json'),data);return
 except ValueError as e:raise SystemExit(str(e))
 app=QApplication(sys.argv);app.setApplicationName('Idle Miner');app.setDesktopFileName('idle-miner');app.setQuitOnLastWindowClosed(False)
 w=Window('--offline-ui-test' in sys.argv,coordinator=coordinator);w.apply_visibility()
 if '--offline-ui-test' not in sys.argv:QTimer.singleShot(0,lambda:w.apply_startup(sys.argv[1:]))
 if '--update-result' in sys.argv:
  def show_update_result():
   try:
    from shared_tray import read_json
    result=STATE/'update-result.json';message=read_json(result).get('message','');result.unlink(missing_ok=True)
    if isinstance(message,str) and message and len(message)<=6000:w.show_stats();QMessageBox.information(w,'Idle Miner update',message)
   except (OSError,ValueError):pass
  QTimer.singleShot(100,show_update_result)
 signal.signal(signal.SIGTERM,lambda *a:w.quit());signal.signal(signal.SIGINT,lambda *a:w.quit())
 if '--offline-ui-test' in sys.argv:
  def capture():w.grab().save('/tmp/idle-miner-linux.png');print('PASS: Linux UI launched stopped',flush=True);w.quit()
  QTimer.singleShot(2000,capture)
 app.exec()
if __name__=='__main__':main()
