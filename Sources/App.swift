import AppKit

@MainActor class MinerApp:NSObject,NSApplicationDelegate,NSMenuDelegate {
 let baseFolder:URL = {
  if let path=ProcessInfo.processInfo.environment["IDLE_MINER_STATE"] { return URL(fileURLWithPath:path,isDirectory:true) }
  return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Idle Miner",isDirectory:true)
 }()
 let profileName=ProfileCoordinator.profileArgument(CommandLine.arguments)
 var folder:URL { profileName=="default" ? baseFolder : baseFolder.appendingPathComponent("Profiles/\(profileName)",isDirectory:true) }
 var coordinator:ProfileCoordinator?
 var sessionClock=SessionClock()
 var pendingRestart=false
 var ignoreEngineOutput=false
 var lastSettingsData:Data?
 var lastIconText=""
 var currencyMenus=[NSMenu]()
 let dockCheck=NSButton(checkboxWithTitle:"Show Dock icon",target:nil,action:nil)
 let menuBarCheck=NSButton(checkboxWithTitle:"Show menu bar icon",target:nil,action:nil)
 var dockItem:NSMenuItem!
 var menuBarItem:NSMenuItem!
 lazy var walletFields:[String:NSTextField]=["LTC":walletField,"DOGE":NSTextField(),"BTC":NSTextField()]
 var editingWallets=[String:String]()
 var settings=Settings()
 var sensors=Sensors()
 var engine:Engine!
 var statusItem:NSStatusItem!
 let stateItem=NSMenuItem(title:"Stopped",action:nil,keyEquivalent:"")
 let healthItem=NSMenuItem(title:"Mining is stopped",action:nil,keyEquivalent:"")
 let rateItem=NSMenuItem(title:"No mining activity",action:nil,keyEquivalent:"")
 let sharesItem=NSMenuItem(title:"No accepted work this session",action:nil,keyEquivalent:"")
 let menuSummary=MenuSummary()
 var startItem:NSMenuItem!
 var boostItem:NSMenuItem!
 var cancelBoostItem:NSMenuItem!
 var boost:TimedBoost?
 var aboutWindow:NSWindow?
 var timer:Timer?
 var activity:NSObjectProtocol?
 var enabled=false
 var desiredThreads=0
 var loadGovernor=LoadGovernor()
 var quitting=false
 var fatalError:String?
 var benchmarkDeadline:Date?
 var benchmarkThreads=0
 var rate="—"
 var accepted=0
 var localStats=LocalMiningStats()
 var lastHealthLevel:MiningHealth.Level?
 let statsService=StatsService()
 var statsWindow:StatsWindow?
 var engineResources:URL { Bundle.main.resourceURL! }
 var statisticsNetworkingEnabled:Bool { Bundle.main.bundleIdentifier=="local.jeff.idleminer" }
 let priceItem=NSMenuItem(title:"Coin price · loading…",action:nil,keyEquivalent:"")
 let balanceItem=NSMenuItem(title:"Pool balance · checking…",action:nil,keyEquivalent:"")
 var window:NSWindow?
 var loginManager:any LoginItemManaging=SystemLoginItem()
 var loginItem:NSMenuItem!
 var loginApprovalItem:NSMenuItem!
 let loginCheck=NSButton(checkboxWithTitle:"Start at Login",target:nil,action:nil)
 let loginHint=NSTextField(wrappingLabelWithString:"")
 let loginApprovalButton=NSButton(title:"Open Login Items…",target:nil,action:nil)
 let coinField=NSPopUpButton()
 let walletField=NSTextField()
 let threadsField=NSPopUpButton()
 let activeCheck=NSButton(checkboxWithTitle:"Pause mining completely while I’m using the Mac",target:nil,action:nil)
 let guidance=NSTextField(wrappingLabelWithString:"")
 let formError=NSTextField(wrappingLabelWithString:"")
 var settingsURL:URL { baseFolder.appendingPathComponent("settings.json") }
 func applicationDidFinishLaunching(_ notification:Notification) {
  do { coordinator=try ProfileCoordinator(base:baseFolder,profile:profileName) }
  catch {
   if ProfileCoordinator.existingPID(base:baseFolder,profile:profileName)==nil { alert(error.localizedDescription) }
   DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.jeff.idleminer.showProfile"),object:profileName,userInfo:nil,deliverImmediately:true)
   NSApp.terminate(nil);return
  }
  do { settings=try Settings.load(from:settingsURL);lastSettingsData=try? Data(contentsOf:settingsURL) } catch { fatalError=error.localizedDescription }
  if profileName != "default" { settings.switchCoin(to:profileName) }
  DistributedNotificationCenter.default().addObserver(self,selector:#selector(showProfile(_:)),name:Notification.Name("local.jeff.idleminer.showProfile"),object:profileName)
  engine=Engine(resources:engineResources,folder:folder.appendingPathComponent("Logs",isDirectory:true))
  engine.leaseURL=coordinator?.engineLeaseURL
  engine.onLine={ [weak self] line in self?.readLine(line) }
  engine.onFault={ [weak self] message in self?.fatalError=message; self?.enabled=false; self?.boost=nil; self?.benchmarkDeadline=nil;self?.sessionClock.stop() }
  engine.onExit={ [weak self] code,requested in
   guard let self=self else { return }
   if Completion.isFailure(code:code,requested:requested,benchmark:self.benchmarkDeadline != nil) {
    self.enabled=false; self.benchmarkDeadline=nil; self.boost=nil
    self.fatalError="Engine exited (\(code)). Review the log before restarting."
   } else if !requested { self.benchmarkDeadline=nil;self.sessionClock.stop() }

   self.ignoreEngineOutput=false
   self.sessionClock.sample(hashing:false)
   self.localStats.engineStopped()
   if !self.enabled || self.pendingRestart { self.coordinator?.releaseCoin() }
   if self.fatalError != nil { self.sessionClock.stop() }
   if self.pendingRestart && requested && !self.quitting { self.pendingRestart=false;self.startMining();return }
   if self.quitting { NSApp.reply(toApplicationShouldTerminate:true); return }
   self.tick()
  }
  makeMenus()
  applyVisibility()
  refreshLoginItem()
  statsService.updated={ [weak self] in self?.updateStatistics() }
  statsService.configure(coin:settings.coin,address:settings.address)
  let center=NSWorkspace.shared.notificationCenter
  center.addObserver(self,selector:#selector(willSleep),name:NSWorkspace.willSleepNotification,object:nil)
  center.addObserver(self,selector:#selector(didWake),name:NSWorkspace.didWakeNotification,object:nil)
  let t=Timer(timeInterval:1,repeats:true){ [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
  RunLoop.main.add(t,forMode:.common); timer=t
  tick()
  if let argument=CommandLine.arguments.first(where:{$0.hasPrefix("--boost-minutes=")}),
     let minutes=Int(argument.dropFirst("--boost-minutes=".count)), TimedBoost.durations.contains(minutes) {
   beginBoost(minutes:minutes)
  } else if CommandLine.arguments.contains("--start-mining") { startMining() }
  if CommandLine.arguments.contains("--show-stats") { showStatistics() }
  if CommandLine.arguments.contains("--show-settings") { showSettings() }
 }
 func makeMenus() {
  let main=NSMenu(); let edit=NSMenu(title:"Edit"); let editItem=NSMenuItem(); editItem.submenu=edit
  for (title,sel,key) in [("Undo",Selector(("undo:")),"z"),("Cut",#selector(NSText.cut(_:)),"x"),("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] { edit.addItem(NSMenuItem(title:title,action:sel,keyEquivalent:key)) }
  main.addItem(editItem); NSApp.mainMenu=main
  statusItem=NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
  statusItem.button?.title="₿"; statusItem.button?.toolTip="Idle Miner"
  let menu=NSMenu(); menu.autoenablesItems=false; menu.delegate=self
  let summaryItem=NSMenuItem(); summaryItem.view=menuSummary; menu.addItem(summaryItem)
  menu.addItem(.separator())
  startItem=add("Start Mining",#selector(startMining),to:menu)
  _=add("Stop Mining",#selector(stopMining),to:menu)
  let boostMenu=NSMenu(title:"Boost Mining"); boostMenu.autoenablesItems=false
  for minutes in TimedBoost.durations {
   let item=add(TimedBoost.label(minutes:minutes),#selector(startBoost(_:)),to:boostMenu); item.tag=minutes
  }
  boostItem=NSMenuItem(title:"Boost Mining",action:nil,keyEquivalent:""); boostItem.submenu=boostMenu; menu.addItem(boostItem)
  cancelBoostItem=add("End Boost · Return to Automatic",#selector(endBoost),to:menu); cancelBoostItem.isHidden=true
  addCurrencyMenus(to:menu)
  _=add("Settings…",#selector(showSettings),key:",",to:menu)
  dockItem=add("Show Dock Icon",#selector(toggleDock),to:menu)
  menuBarItem=add("Show Menu Bar Icon",#selector(toggleMenuBar),to:menu)
  loginItem=add("Start at Login",#selector(toggleLoginItem),to:menu)
  loginApprovalItem=add("Approve Login Item in System Settings…",#selector(openLoginSettings),to:menu); loginApprovalItem.isHidden=true
  let benchmark=NSMenu(title:"Offline Benchmark"); benchmark.autoenablesItems=false
  for count in [1,2,4,8,12] {
   let entry=add("\(count) thread\(count==1 ? "" : "s") · up to 70 seconds",#selector(startBenchmark(_:)),to:benchmark); entry.tag=count
  }
  let benchItem=NSMenuItem(title:"Offline Benchmark",action:nil,keyEquivalent:""); benchItem.submenu=benchmark; menu.addItem(benchItem)
  menu.addItem(.separator())
  _=add("Mining Stats…",#selector(showStatistics),to:menu)
  _=add("View Pool Payouts…",#selector(openPool),to:menu)
  _=add("Show Latest Log",#selector(showLog),to:menu)
  _=add("Wallet & Payout Help",#selector(showHelp),to:menu)
  _=add("About Idle Miner",#selector(showAbout),to:menu)
  menu.addItem(.separator()); _=add("Quit Idle Miner",#selector(quitApp),key:"q",to:menu)
  statusItem.menu=menu
  let appMenu=NSMenu(title:"Idle Miner");appMenu.autoenablesItems=false
  _=add("Mining Stats…",#selector(showStatistics),to:appMenu)
  _=add("Start Mining",#selector(startMining),to:appMenu);_=add("Stop Mining",#selector(stopMining),to:appMenu)
  addCurrencyMenus(to:appMenu)
  _=add("Settings…",#selector(showSettings),key:",",to:appMenu)
  _=add("About Idle Miner",#selector(showAbout),to:appMenu)
  appMenu.addItem(.separator());_=add("Quit Idle Miner",#selector(quitApp),key:"q",to:appMenu)
  let appItem=NSMenuItem();appItem.submenu=appMenu;main.insertItem(appItem,at:0)
 }
 @discardableResult func add(_ title:String,_ action:Selector,key:String="",to menu:NSMenu)->NSMenuItem {
  let item=NSMenuItem(title:title,action:action,keyEquivalent:key); item.target=self; menu.addItem(item); return item
 }
 @objc func startMining() {
  guard !engine.running else { return }
  guard Wallet.valid(settings.address,coin:settings.coin) else { showSettings(); formError.stringValue="Paste your public \(settings.coin) Receive address, then save."; return }
  guard coordinator?.claimCoin(settings.coin) != false else { alert("Another Idle Miner instance is already mining \(settings.coin). Stop it or select a different currency.");return }
  sessionClock.begin();pendingRestart=false
  loadGovernor.reset(); localStats.reset(); enabled=true; boost=nil; fatalError=nil; benchmarkDeadline=nil; accepted=0; rate="—"; tick()
 }
 @objc func startBoost(_ sender:NSMenuItem) { beginBoost(minutes:sender.tag) }
 func beginBoost(minutes:Int) {
  guard let session=TimedBoost(minutes:minutes,now:BoostClock.now) else { return }
  guard benchmarkDeadline==nil else { alert("Stop the offline benchmark before starting Boost."); return }
  guard Wallet.valid(settings.address,coin:settings.coin) else { showSettings(); formError.stringValue="Save your public receive address before starting Boost."; return }
  if !enabled {
   guard coordinator?.claimCoin(settings.coin) != false else { alert("Another instance is already mining \(settings.coin).");return }
   sessionClock.begin();localStats.reset(); accepted=0; rate="—"
  }
  loadGovernor.reset(); boost=session; enabled=true; fatalError=nil; tick()
 }
 @objc func endBoost() { boost=nil; tick() }
 @objc func stopMining() {
  pendingRestart=false;sessionClock.stop();fatalError=nil;enabled=false;boost=nil;benchmarkDeadline=nil;engine.stop()
  if !engine.running { coordinator?.releaseCoin() };tick()
 }
 @objc func startBenchmark(_ sender:NSMenuItem) {
  guard !engine.running else { alert("Stop the current mining session before starting a benchmark."); return }
  let e=sensors.sample()
  guard e.onAC && e.thermal<2 && !e.memoryPressure && !e.sleeping else { alert(Policy.pauseReason(e)); return }
  sessionClock.begin();localStats.reset(); enabled=false; boost=nil; fatalError=nil; accepted=0; rate="—"
  benchmarkThreads=min(sender.tag,max(1,e.cores-2)); benchmarkDeadline=Date().addingTimeInterval(70)
  tick()
 }
 func tick() {
  guard engine != nil else { return }
  refreshSharedSettings()
  sessionClock.sample(hashing:engine.ready && !engine.isStopping && !engine.isChanging && (localStats.currentRate() ?? 0)>0)
  if statisticsNetworkingEnabled { statsService.refresh(coin:settings.coin,address:settings.address) }
  defer { updateStatistics() }
  let e=sensors.sample()
  desiredThreads=0
  let now=BoostClock.now
  if let session=boost, !session.isActive(at:now) { boost=nil }
  cancelBoostItem.isHidden=boost==nil
  boostItem.title="Boost Mining · up to \(settings.idleThreads) Threads"
  if let items=boostItem.submenu?.items { for item in items { item.isEnabled=benchmarkDeadline==nil } }
  if engine.running && activity == nil {
   activity=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Respond to activity during user-started mining")
  } else if !engine.running, let token=activity {
   ProcessInfo.processInfo.endActivity(token); activity=nil
  }
  if let end=benchmarkDeadline {
   if Date()>=end || !e.onAC || e.thermal>=2 || e.memoryPressure || e.sleeping {
    benchmarkDeadline=nil; sessionClock.stop();engine.stop()
   } else {
    let quota=sharedQuota(request:benchmarkThreads,cores:e.cores)
    desiredThreads=quota
    if !engine.running && quota>0 {
     do { localStats.engineStarted(offline:true);try engine.start(settings:Settings(),threads:quota,benchmark:true) }
     catch { fatalError=error.localizedDescription;benchmarkDeadline=nil;sessionClock.stop() }
    } else if engine.ready && engine.threads != quota {
     if quota==0 { engine.stop() } else { do { try engine.changeThreads(to:quota);localStats.threadsChanged() } catch { fatalError=error.localizedDescription;benchmarkDeadline=nil;sessionClock.stop();engine.stop() } }
    }
    engine.checkTransitionTimeout()
    stateItem.title=quota>0 ? "Offline benchmark · \(quota) threads" : "Offline benchmark · waiting for shared CPU capacity"
    rateItem.title="RandomX: \(rate) H/s · \(max(0,Int(end.timeIntervalSinceNow)))s left"
    sharesItem.title="Offline test · no earnings"
    startItem.isEnabled=false; return
   }
  }
  engine.checkTransitionTimeout()
  loadGovernor.observe(utilization:e.cpuUtilization,threads:engine.threads,ready:engine.ready && !engine.isStopping,now:now)
  let request=enabled ? Policy.threads(settings,e,boost:boost != nil,ceiling:loadGovernor.ceiling) : 0
  let desired=sharedQuota(request:request,cores:e.cores)
  desiredThreads=desired
  if engine.running && !engine.isStopping && engine.threads != desired {
   if desired==0 || (!engine.ready && !engine.isChanging && desired<engine.threads) { engine.stop() }
   else if engine.ready {
    do { try engine.changeThreads(to:desired); localStats.threadsChanged() }
    catch { fatalError=error.localizedDescription; enabled=false; boost=nil; engine.stop() }
   }
  }
  if enabled && desired>0 && !engine.running {
   guard coordinator?.claimCoin(settings.coin) != false else { enabled=false;fatalError="Another instance is already mining \(settings.coin).";sessionClock.stop();return }
   do { rate="—"; localStats.engineStarted(offline:false); try engine.start(settings:settings,threads:desired,benchmark:false) }
   catch { enabled=false; boost=nil; fatalError=error.localizedDescription;sessionClock.stop();localStats.engineStopped();coordinator?.releaseCoin();_=sharedQuota(request:0,cores:e.cores) }
  }
  if let problem=fatalError { stateItem.title="Stopped · \(problem)" }
  else if !enabled { stateItem.title=engine.running ? "Stopping…" : "Stopped" }
  else if desired==0 { stateItem.title=request>0 ? "Waiting for shared CPU capacity" : Policy.pauseReason(e) }
  else if boost != nil { stateItem.title="Boost mining · \(desired) thread\(desired==1 ? "" : "s")" }
  else { stateItem.title=desired==1 ? "Mining lightly · 1 thread" : "Mining while idle · \(desired) threads" }
  if enabled && desired>0 && loadGovernor.ceiling<settings.idleThreads { stateItem.title += " · reduced for CPU load" }
  if let session=boost { stateItem.title += " · \(session.countdown(at:now)) left" }
  rateItem.title=engine.running ? "RandomX: \(rate) H/s → \(settings.coin)" : "Payout currency: \(settings.coin)"
  sharesItem.title="Pool-accepted shares this session: \(localStats.accepted)"
  startItem.isEnabled = !enabled && !engine.running
  statusItem.button?.toolTip="Idle Miner · \(settings.coin) · \(stateItem.title)"
  for menu in currencyMenus { for item in menu.items { item.state=item.representedObject as? String==settings.coin ? .on : .off } }
 }
 func readLine(_ line:String) {
  guard !ignoreEngineOutput else { return }
  localStats.consume(line)
  accepted=localStats.accepted
  rate=localStats.currentRate().map{String(format:"%.1f",$0)} ?? "—"
 }
 @objc func willSleep() { sessionClock.sample(hashing:false);sensors.sleeping=true; engine.stop(); tick() }
 @objc func didWake() { sensors.sleeping=false; sensors.lastWake=Date(); tick() }
 @objc func showLog() { if let url=engine.logURL { NSWorkspace.shared.open(url) } else { alert("No log yet. Start an offline benchmark or a configured mining session first.") } }
 @objc func openPool() {
  guard Wallet.valid(settings.address,coin:settings.coin) else { showSettings(); return }
  let address=settings.address.addingPercentEncoding(withAllowedCharacters:.urlPathAllowed)!
  NSWorkspace.shared.open(URL(string:"https://unmineable.com/coins/\(settings.coin)/address/\(address)")!)
 }
 @objc func showHelp() { if let url=Bundle.main.url(forResource:"Help",withExtension:"html") { NSWorkspace.shared.open(url) } }
 @objc func showAbout() {
  if aboutWindow==nil {
   let w=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:470),styleMask:[.titled,.closable],backing:.buffered,defer:false)
   w.title="About Idle Miner"; w.isReleasedWhenClosed=false; w.center(); aboutWindow=w
   let stack=NSStackView(); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing=10
   stack.translatesAutoresizingMaskIntoConstraints=false; w.contentView!.addSubview(stack)
   NSLayoutConstraint.activate([stack.centerXAnchor.constraint(equalTo:w.contentView!.centerXAnchor),stack.centerYAnchor.constraint(equalTo:w.contentView!.centerYAnchor),stack.widthAnchor.constraint(equalToConstant:392)])
   let icon=NSImageView(); icon.image=Bundle.main.url(forResource:"IdleMiner",withExtension:"icns").flatMap{NSImage(contentsOf:$0)} ?? NSApp.applicationIconImage
   icon.imageScaling = .scaleProportionallyUpOrDown
   stack.addArrangedSubview(icon); icon.widthAnchor.constraint(equalToConstant:100).isActive=true; icon.heightAnchor.constraint(equalToConstant:100).isActive=true
   func centered(_ text:String,size:CGFloat=12,bold:Bool=false,secondary:Bool=false) {
    let field=NSTextField(wrappingLabelWithString:text); field.alignment = .center
    field.font=bold ? .boldSystemFont(ofSize:size) : .systemFont(ofSize:size)
    if secondary { field.textColor = .secondaryLabelColor }
    stack.addArrangedSubview(field); field.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
   }
   let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.6.1"
   let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "9"
   centered("Idle Miner",size:24,bold:true)
   centered("By Jeffry Zander",size:14)
   centered("Version \(version) (\(build))",secondary:true)
   centered("A miner that yields to your Mac.",size:13)
   centered("CPU mining: RandomX / Monero\nPayouts: selected coin through unMineable")
   centered("XMRig 6.26.0 · GPLv3 · 1% developer donation\nProvider fees and withdrawal thresholds also apply.",secondary:true)
   centered("No guaranteed earnings or profit.",secondary:true)
  }
  NSApp.activate(ignoringOtherApps:true); aboutWindow?.makeKeyAndOrderFront(nil)
 }
 @objc func quitApp() { NSApp.terminate(nil) }
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
  enabled=false; boost=nil; benchmarkDeadline=nil; timer?.invalidate()
  if engine?.running == true { quitting=true; engine.stop(); return .terminateLater }
  return .terminateNow
 }
 func alert(_ text:String) {
  NSApp.activate(ignoringOtherApps:true); let a=NSAlert(); a.messageText="Idle Miner"; a.informativeText=text; a.runModal()
 }
 @objc func showSettings() {
  refreshSharedSettings()
  if window==nil { makeSettingsWindow() }
  coinField.selectItem(withTitle:settings.coin)
  editingWallets=settings.wallets
  for (currency,field) in walletFields { field.stringValue=settings.wallets[currency] ?? (settings.coin==currency ? settings.address : "") }
  dockCheck.state=settings.showDock ? .on : .off;menuBarCheck.state=settings.showMenuBar ? .on : .off
  threadsField.selectItem(withTag:settings.idleThreads); activeCheck.state=settings.pauseWhileActive ? .on : .off
  formError.stringValue=""; updateGuidance(); refreshLoginItem()
  NSApp.activate(ignoringOtherApps:true); window?.makeKeyAndOrderFront(nil)
  window?.makeFirstResponder(walletField)
 }
 func label(_ text:String,_ bold:Bool=false)->NSTextField {
  let field=NSTextField(wrappingLabelWithString:text); field.font=bold ? .boldSystemFont(ofSize:13) : .systemFont(ofSize:12); return field
 }
 func makeSettingsWindow() {
  let w=NSWindow(contentRect:NSRect(x:0,y:0,width:630,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
  w.title="Idle Miner Settings";w.isReleasedWhenClosed=false;w.center();window=w
  let scroll=NSScrollView(frame:w.contentView!.bounds);scroll.autoresizingMask=[.width,.height];scroll.hasVerticalScroller=true;scroll.autohidesScrollers=true;scroll.drawsBackground=false;w.contentView!.addSubview(scroll)
  let document=StatsDocument();document.translatesAutoresizingMaskIntoConstraints=false;scroll.documentView=document
  document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor).isActive=true
  let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=9;stack.translatesAutoresizingMaskIntoConstraints=false;document.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:document.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:document.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:document.topAnchor,constant:22),stack.bottomAnchor.constraint(equalTo:document.bottomAnchor,constant:-20)])
  func row(_ view:NSView) { stack.addArrangedSubview(view);view.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true }
  let title=label("₿  Idle Miner",true);title.font = .boldSystemFont(ofSize:22);row(title)
  row(label("Save each native-network Receive address. Switch currency from the menu; open another currency to mine both."))
  row(label("Currency for this instance",true));coinField.addItems(withTitles:Settings.coins);coinField.target=self;coinField.action=#selector(coinChanged);row(coinField)
  for currency in Settings.coins {
   row(label("\(currency) public Receive address",true))
   let field=walletFields[currency]!;field.placeholderString="Optional · paste the native \(currency) Receive address";row(field)
  }
  guidance.font = .systemFont(ofSize:12);guidance.textColor = .secondaryLabelColor;row(guidance)
  row(label("Total idle / boost threads shared across instances",true))
  for n in [2,4,8,12] { threadsField.addItem(withTitle:"\(n) threads");threadsField.lastItem!.tag=n };row(threadsField)
  row(activeCheck);row(dockCheck);row(menuBarCheck)
  loginCheck.allowsMixedState=true;loginCheck.target=self;loginCheck.action=#selector(toggleLoginItem);row(loginCheck)
  loginHint.font = .systemFont(ofSize:12);loginHint.textColor = .secondaryLabelColor;row(loginHint)
  loginApprovalButton.target=self;loginApprovalButton.action=#selector(openLoginSettings);loginApprovalButton.isHidden=true;stack.addArrangedSubview(loginApprovalButton)
  row(label("Each currency uses a separate mining dataset (about 2 GB). Running instances share the total thread limit and reserve two CPU cores where possible. Active-use, battery, sleep, heat and memory protections still apply. Keep a Dock or menu bar icon enabled."))
  formError.textColor = .systemRed;formError.font = .systemFont(ofSize:12);row(formError)
  let buttons=NSStackView();buttons.orientation = .horizontal;buttons.spacing=12
  buttons.addArrangedSubview(NSButton(title:"Wallet & Payout Help",target:self,action:#selector(showHelp)))
  let save=NSButton(title:"Save Settings",target:self,action:#selector(saveSettings));save.keyEquivalent="\r";buttons.addArrangedSubview(save);stack.addArrangedSubview(buttons)
 }
 @objc func coinChanged() { updateGuidance();formError.stringValue="Saving selects this currency and stops the current session." }
 func updateGuidance() {
  let coin=coinField.titleOfSelectedItem ?? "LTC"
  if coin=="LTC" { guidance.stringValue="Recommended: Robinhood → Litecoin → Receive. Use the Litecoin network (L…, M…, or ltc1q…). Never paste your Bitcoin address here." }
  else if coin=="BTC" { guidance.stringValue="Robinhood → Bitcoin → Receive. Native Bitcoin only (1…, 3…, or bc1q…). BTC has a high provider payout minimum; no Lightning or Taproot." }
  else { guidance.stringValue="Robinhood → Dogecoin → Receive. Use the native Dogecoin network and a D… address. Check the provider’s payout minimum." }
 }
 @objc func saveSettings() {
  var next=settings;next.coin=coinField.titleOfSelectedItem ?? "LTC"
  var changes=[String:String]()
  for (currency,field) in walletFields {
   let value=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);next.wallets[currency]=value
   if value != (editingWallets[currency] ?? "") { changes[currency]=value }
  }
  next.address=next.wallets[next.coin] ?? ""
  next.idleThreads=threadsField.selectedTag();next.pauseWhileActive=activeCheck.state == .on
  next.showDock=dockCheck.state == .on;next.showMenuBar=menuBarCheck.state == .on
  do {
   try next.save(to:settingsURL,walletChanges:changes,updateDefaultCoin:profileName=="default")
   ignoreEngineOutput=engine.running;stopMining();settings=try Settings.load(from:settingsURL);settings.switchCoin(to:next.coin)
   lastSettingsData=try? Data(contentsOf:settingsURL);sessionClock=SessionClock(launchedAt:sessionClock.launchedAt);localStats.reset();statsService.configure(coin:settings.coin,address:settings.address)
   fatalError=nil;applyVisibility();window?.orderOut(nil);tick()
  } catch { formError.stringValue=error.localizedDescription }
 }
}
