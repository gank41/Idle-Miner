import AppKit

extension MinerApp {
 func addCurrencyMenus(to menu:NSMenu) {
  let choices=NSMenu(title:"Switch Currency");choices.autoenablesItems=false
  for coin in Settings.coins {
   let item=add(coin,#selector(switchCurrency(_:)),to:choices);item.representedObject=coin
  }
  currencyMenus.append(choices)
  let switchItem=NSMenuItem(title:"Switch Currency",action:nil,keyEquivalent:"");switchItem.submenu=choices;menu.addItem(switchItem)
  let others=NSMenu(title:"Open Another Currency");others.autoenablesItems=false
  for coin in Settings.coins { let item=add(coin,#selector(openCurrency(_:)),to:others);item.representedObject=coin }
  let openItem=NSMenuItem(title:"Open Another Currency…",action:nil,keyEquivalent:"");openItem.submenu=others;menu.addItem(openItem)
 }
 func sharedQuota(request:Int,cores:Int)->Int {
  do { return try coordinator?.quota(requested:request,actual:engine.reservedThreads,budget:settings.idleThreads,cores:cores) ?? request }
  catch { enabled=false;benchmarkDeadline=nil;pendingRestart=false;fatalError=error.localizedDescription;engine.stop();sessionClock.stop();return 0 }
 }
 @objc func showProfile(_ notification:Notification) { if notification.userInfo?["view"] as? String == "settings" { showSettings() } else { showStatistics() } }
 @objc func switchCurrency(_ sender:NSMenuItem) {
  guard let coin=sender.representedObject as? String,coin != settings.coin else { return }
  refreshSharedSettings()
  let resume=enabled
  var next=settings;next.switchCoin(to:coin)
  do {
   try next.save(to:settingsURL,walletChanges:[:],updateDefaultCoin:profileName=="default")
   next=try Settings.load(from:settingsURL);next.switchCoin(to:coin)
  }
  catch { alert(error.localizedDescription);return }
  ignoreEngineOutput=engine.running;stopMining();settings=next;lastSettingsData=try? Data(contentsOf:settingsURL)
  sessionClock=SessionClock(launchedAt:sessionClock.launchedAt);localStats.reset();statsService.configure(coin:coin,address:next.address)
  if !Wallet.valid(next.address,coin:coin) { showSettings();formError.stringValue="Save a native \(coin) Receive address to mine this currency.";return }
  pendingRestart=resume
  if !engine.running && pendingRestart { pendingRestart=false;startMining() }
  tick()
 }
 @objc func openCurrency(_ sender:NSMenuItem) {
  guard let coin=sender.representedObject as? String else { return }
  openCurrencyInstance(coin,startMining:false,showStats:true)
 }
 func openCurrencyInstance(_ coin:String,startMining:Bool,showStats:Bool,showSettings:Bool=false,boostMinutes:Int?=nil) {
  guard Settings.coins.contains(coin) else { return }
  if settings.coin==coin {
   if boostMinutes != nil { performCurrencyCommand("boost",minutes:boostMinutes) }
   else if startMining { self.startMining() }
   if showSettings { self.showSettings() } else if showStats { showStatistics() };return
  }
  // A profile is a stable process slot, not proof of its current payout currency.
  if sharedMenuStore==nil { sharedMenuStore=try? SharedMenuStore(base:baseFolder,profile:profileName) }
  if let peer=sharedMenuStore?.snapshots().filter({$0.coin==coin}).max(by:{$0.rank<$1.rank}) {
   do {
    if let minutes=boostMinutes { try sharedMenuStore?.send(peer,action:"boost",minutes:minutes) }
    else if startMining { try sharedMenuStore?.send(peer,action:"start") }
    if showStats || showSettings { try sharedMenuStore?.send(peer,action:showSettings ? "settings":"stats") }
   } catch { alert(error.localizedDescription) };return
  }
  let candidates=[coin]+(["default"]+Settings.coins).filter{$0 != coin}
  guard let slot=candidates.first(where:{$0 != profileName && ProfileCoordinator.existingPID(base:baseFolder,profile:$0)==nil}) else {
   alert("All currency process slots are occupied. Close an unused currency instance, then open \(coin) again.");return
  }
  let configuration=NSWorkspace.OpenConfiguration();configuration.createsNewApplicationInstance=true
  configuration.arguments=["--profile=\(slot)"]+(slot==coin ? [] : ["--currency=\(coin)"])+(boostMinutes.map{TimedBoost.durations.contains($0) ? ["--boost-minutes=\($0)"] : []} ?? (startMining ? ["--start-mining"] : []))+(showStats ? ["--show-stats"] : [])+(showSettings ? ["--show-settings"] : [])
  configuration.activates=showStats || showSettings
  if let handler=profileLaunchHandler { handler(coin,configuration.arguments);return }
  NSWorkspace.shared.openApplication(at:Bundle.main.bundleURL,configuration:configuration) { _,error in
   if let error=error { DispatchQueue.main.async { self.alert("Could not open another instance. \(error.localizedDescription)") } }
  }
 }
 func applyVisibility() {
  NSApp.setActivationPolicy(settings.showDock ? .regular : .accessory)
  if !settings.showMenuBar { statusItem?.isVisible=false;sharedMenuStore?.releaseOwnership() }
  dockItem?.state=settings.showDock ? .on : .off;menuBarItem?.state=settings.showMenuBar ? .on : .off
  dockCheck.state=settings.showDock ? .on : .off;menuBarCheck.state=settings.showMenuBar ? .on : .off
 }
 func saveVisibility(dock:Bool,menu:Bool) {
  guard dock || menu else { alert("Keep the Dock icon, menu bar icon, or both enabled.");return }
  var next=settings;next.showDock=dock;next.showMenuBar=menu
  do {
   try next.save(to:settingsURL,walletChanges:[:],updateDefaultCoin:false)
   lastSettingsData=nil;refreshSharedSettings();applyVisibility();updateStatistics()
  } catch { alert(error.localizedDescription) }
 }
 @objc func toggleDock() { saveVisibility(dock:!settings.showDock,menu:settings.showMenuBar) }
 @objc func toggleMenuBar() { saveVisibility(dock:settings.showDock,menu:!settings.showMenuBar) }
 func refreshSharedSettings() {
  guard let data=try? Data(contentsOf:settingsURL),data != lastSettingsData else { return }
  do {
   var fresh=try Settings.load(from:settingsURL);fresh.switchCoin(to:settings.coin)
   let walletChanged=fresh.address != settings.address
   lastSettingsData=data
   if walletChanged && (enabled || engine?.running == true) {
    ignoreEngineOutput=engine.running;stopMining();fatalError="This wallet was changed in another instance. Check Settings, then Start Mining."
   }
   settings=fresh;applyVisibility()
   if walletChanged { sessionClock=SessionClock(launchedAt:sessionClock.launchedAt);localStats.reset();statsService.configure(coin:fresh.coin,address:fresh.address) }
  } catch { lastSettingsData=data;stopMining();fatalError="Shared settings could not be loaded: \(error.localizedDescription)" }
 }
 func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { showStatistics();return true }
 func applicationDockMenu(_ sender:NSApplication)->NSMenu? {
  let menu=NSMenu();menu.autoenablesItems=false
  _=add("Mining Stats…",#selector(showStatistics),to:menu)
  _=add("Start Mining",#selector(startMining),to:menu);_=add("Stop Mining",#selector(stopMining),to:menu)
  addCurrencyMenus(to:menu);_=add("Settings…",#selector(showSettings),to:menu);return menu
 }
}
