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
 @objc func showProfile(_ notification:Notification) { showStatistics() }
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
  if settings.coin==coin { showStatistics();return }
  if let pid=ProfileCoordinator.existingPID(base:baseFolder,profile:coin) {
   DistributedNotificationCenter.default().postNotificationName(Notification.Name("local.jeff.idleminer.showProfile"),object:coin,userInfo:nil,deliverImmediately:true)
   NSRunningApplication(processIdentifier:pid)?.activate(options:[]);return
  }
  let configuration=NSWorkspace.OpenConfiguration();configuration.createsNewApplicationInstance=true
  configuration.arguments=["--profile=\(coin)","--show-stats"]
  NSWorkspace.shared.openApplication(at:Bundle.main.bundleURL,configuration:configuration) { _,error in
   if let error=error { DispatchQueue.main.async { self.alert("Could not open another instance. \(error.localizedDescription)") } }
  }
 }
 func applyVisibility() {
  NSApp.setActivationPolicy(settings.showDock ? .regular : .accessory)
  statusItem?.isVisible=settings.showMenuBar
  dockItem?.state=settings.showDock ? .on : .off;menuBarItem?.state=settings.showMenuBar ? .on : .off
  dockCheck.state=settings.showDock ? .on : .off;menuBarCheck.state=settings.showMenuBar ? .on : .off
 }
 func saveVisibility(dock:Bool,menu:Bool) {
  guard dock || menu else { alert("Keep the Dock icon, menu bar icon, or both enabled.");return }
  var next=settings;next.showDock=dock;next.showMenuBar=menu
  do {
   try next.save(to:settingsURL,walletChanges:[:],updateDefaultCoin:false)
   lastSettingsData=nil;refreshSharedSettings();applyVisibility()
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
