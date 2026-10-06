import AppKit
import ServiceManagement
@MainActor final class FakeLoginItem:LoginItemManaging {
 var status:SMAppService.Status = .notRegistered
 var changes=[Bool]()
 var needsApproval=false
 var opened=false
 var fail=false
 func setEnabled(_ enabled:Bool)throws {
  if fail { throw MinerError.message("Test registration failure") }
  changes.append(enabled); status=enabled ? (needsApproval ? .requiresApproval : .enabled) : .notRegistered
 }
 func openSystemSettings() { opened=true }
}
class SmokeApp:MinerApp {
 var lastAlert:String?
 override func alert(_ text:String) { lastAlert=text }
 override func applicationDidFinishLaunching(_ n:Notification) {
  loginManager=FakeLoginItem()
  super.applicationDidFinishLaunching(n)
  showSettings()
  let login=loginManager as! FakeLoginItem
  precondition(loginItem.state == .off && loginCheck.state == .off,"Login default state")
  NSApp.sendAction(loginItem.action!,to:loginItem.target,from:loginItem)
  precondition(loginItem.state == .on && loginCheck.state == .on,"Menu and Settings must both enable")
  loginCheck.performClick(nil)
  precondition(loginItem.state == .off && loginCheck.state == .off,"Menu and Settings must both disable")
  login.needsApproval=true; toggleLoginItem()
  precondition(loginItem.state == .mixed && loginCheck.state == .mixed && !loginApprovalItem.isHidden,"Pending approval must not appear enabled")
  openLoginSettings(); precondition(login.opened,"Approval link")
  toggleLoginItem(); precondition(login.status == .notRegistered,"Cancel pending request")
  login.status = .enabled; menuWillOpen(statusItem.menu!)
  precondition(loginCheck.state == .on && loginItem.state == .on,"External changes must refresh")
  login.status = .notRegistered; refreshLoginItem()
  login.fail=true; toggleLoginItem()
  precondition(loginItem.state == .off && loginCheck.state == .off && lastAlert?.contains("Test registration failure")==true,"Failed registration must restore controls and report failure")
  login.fail=false
  precondition(!enabled && !engine.running,"Login toggles must not start mining")
  walletField.stringValue="Public receive address hidden in test capture"
  DispatchQueue.main.asyncAfter(deadline:.now()+1) {
   guard let view=self.window?.contentView, let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { print("FAIL: settings did not render"); exit(1) }
   view.cacheDisplay(in:view.bounds,to:bitmap)
   try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/private/tmp/idle-miner-settings.png"))
   guard self.statusItem.button?.title=="₿", self.window?.isVisible==true, self.coinField.titleOfSelectedItem=="LTC", !self.enabled, !self.engine.running else { print("FAIL: UI startup state"); exit(1) }
   self.showStatistics()
   let stats=self.statsWindow!
   precondition(stats.window.isVisible,"Stats window not visible")
   precondition(stats.balance.stringValue.contains("awaiting confirmation"),"Unknown balance shown as zero")
   // Representative test-only samples; never stored as real mining results.
   for i in 0..<80 { self.localStats.append(rate:500+Double(i%20)*30,now:Date().addingTimeInterval(Double(i-80)*5)) }
   self.localStats.accepted=3
   self.statsService.quote=PriceQuote(coin:"LTC",usd:68.246,fetchedAt:Date())
   self.statsService.pool=PoolSnapshot(coin:"LTC",balance:0.00000271,payable:0.00000271,paid:0,rewards24h:0.00000171,threshold:0.00075,automatic:false,payoutIssue:false,workerRate:583,workerOnline:true,fetchedAt:Date())
   self.updateStatistics()
   @MainActor func color()->NSColor? { self.statusItem.button?.attributedTitle.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor }
   precondition(color()==NSColor.systemGray,"A balance must not turn a stopped miner green")
   self.applyMiningHealth(MiningHealth(level:.working,message:"Mining working"))
   precondition(color()==NSColor.systemGreen,"Working icon must be green")
   self.applyMiningHealth(MiningHealth(level:.issue,message:"Connection lost"))
   precondition(color()==NSColor.systemRed && self.healthItem.title=="Connection lost","Issue must be red with explanation")
   self.applyMiningHealth(MiningHealth(level:.inactive,message:"Paused"))
   precondition(color()==NSColor.systemGray,"Paused icon must be gray")
   self.fatalError="Test engine exit"; self.updateStatistics()
   precondition(color()==NSColor.systemRed,"Engine failure must be red")
   self.stopMining(); precondition(color()==NSColor.systemGray,"Explicit stop acknowledges issue and returns gray")
   precondition(stats.balance.stringValue.contains("<$0.01"),"Tiny earnings hidden")
   precondition(stats.threshold.stringValue.contains("Automatic payouts off"),"Manual payout status hidden")
   stats.window.contentView?.layoutSubtreeIfNeeded()
   if let content=stats.window.contentView,let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
    content.cacheDisplay(in:content.bounds,to:bitmap)
    try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/private/tmp/idle-miner-stats.png"))
   }
   precondition(stats.window.styleMask.contains(.resizable),"Mining Stats must be user-resizable")
   let opening=stats.window.contentView!.bounds.size
   stats.window.setContentSize(NSSize(width:760,height:900));stats.window.contentView!.layoutSubtreeIfNeeded()
   if let scroll=stats.window.contentView?.subviews.first as? NSScrollView,let document=scroll.documentView {
    precondition(document.frame.height<=scroll.contentView.bounds.height+1,"All standard Stats content must fit at the larger size")
    stats.window.setContentSize(NSSize(width:640,height:540));stats.window.contentView!.layoutSubtreeIfNeeded()
    precondition(abs(document.frame.width-scroll.contentView.bounds.width)<1,"Stats must reflow to the resized viewport")
    precondition(document.frame.height>scroll.contentView.bounds.height,"Smaller windows retain scrolling to every control")
    let resized=stats.window.contentView!.bounds.size
    self.showStatistics();precondition(stats.window.contentView!.bounds.size==resized,"Reopening Stats preserves the chosen size")
    stats.window.setContentSize(opening);stats.window.contentView!.layoutSubtreeIfNeeded()
    precondition(document.frame.height>100,"Stats document collapsed")
    print("Stats layout: document height \(document.frame.height), window height \(scroll.bounds.height)")
   }
   self.statsService.poolError="Test unavailable"; self.updateStatistics()
   precondition(color()==NSColor.systemGray && stats.balance.stringValue.contains("Last known"),"Stale earnings not labeled")
   self.menuSummary.update(["Boost mining · 8 threads · 0:14:59 left", "Mining is working · fresh hashrate and pool connection", "RandomX: 519.4 H/s → LTC", "Pool-accepted shares this session: 128", "1 LTC ≈ $67.34 USD", "Pool balance: 0.00014792 LTC"])
   precondition(self.statusItem.menu?.items.first?.view === self.menuSummary)
   for theme in [NSAppearance.Name.aqua, .darkAqua] {
    self.menuSummary.appearance=NSAppearance(named:theme)
    let panel=NSWindow(contentRect:self.menuSummary.bounds,styleMask:[.borderless],backing:.buffered,defer:false)
    panel.appearance=NSAppearance(named:theme)
    let material=NSVisualEffectView(frame:self.menuSummary.bounds)
    material.material = .menu; material.state = .active
    panel.contentView=material; material.addSubview(self.menuSummary)
    panel.orderFront(nil); material.layoutSubtreeIfNeeded()
    for label in self.menuSummary.labels {
     precondition(label.textColor == .labelColor && label.frame.maxY <= self.menuSummary.bounds.height)
     precondition(label.cell!.cellSize(forBounds:label.bounds).height <= label.frame.height+1,"Summary text clipped")
    }
    if let bitmap=material.bitmapImageRepForCachingDisplay(in:material.bounds) {
     material.cacheDisplay(in:material.bounds,to:bitmap)
     try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/private/tmp/idle-miner-menu-\(theme.rawValue).png"))
    }
    self.menuSummary.removeFromSuperview(); panel.orderOut(nil)
   }
   self.statusItem.menu?.items.first?.view=self.menuSummary
   self.menuSummary.appearance=nil
   self.showAbout()
   guard let about=self.aboutWindow, let stack=about.contentView?.subviews.first as? NSStackView else { Swift.fatalError("Missing custom About") }
   about.contentView?.layoutSubtreeIfNeeded()
   let labels=stack.arrangedSubviews.compactMap{$0 as? NSTextField}
   precondition(labels.allSatisfy{$0.alignment == .center},"About labels must be centered")
   precondition(labels.map(\.stringValue).contains("By Jeffry Zander"),"Missing byline")
   precondition(stack.frame.minY>=0 && stack.frame.maxY<=about.contentView!.bounds.height,"About clipped")
   precondition(self.boostItem.submenu?.items.map(\.tag)==TimedBoost.durations,"Missing boost durations")
   self.boost=TimedBoost(minutes:15,now:BoostClock.now-901); self.tick()
   precondition(self.boost==nil && self.cancelBoostItem.isHidden,"Expired timer not cleared")
   self.boost=TimedBoost(minutes:15,now:BoostClock.now); self.tick(); self.endBoost()
   precondition(self.boost==nil,"Cancel must clear timer")
   if let content=about.contentView, let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
    content.cacheDisplay(in:content.bounds,to:bitmap)
    try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/private/tmp/idle-miner-about.png"))
   }
   self.showSettings()
   precondition(self.walletFields.count==3,"All currency wallets must be editable together")
   self.walletFields["LTC"]!.stringValue="LKKHMBjCU89fyFNgSRprDoD8Jb25N8uWvd"
   self.walletFields["DOGE"]!.stringValue="D5ERdEN1gsouFSs7zsq7VYJxyWP6dP28H1"
   self.walletFields["BTC"]!.stringValue="1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
   self.coinField.selectItem(withTitle:"BTC")
   self.dockCheck.state = .off;self.menuBarCheck.state = .off;self.saveSettings()
   precondition(self.formError.stringValue.contains("Keep"),"Neither visibility path must be rejected")
   self.dockCheck.state = .on;self.saveSettings()
   precondition(self.settings.coin=="BTC" && self.settings.wallets.count==3,"Save all wallets and select currency")
   precondition(NSApp.activationPolicy() == .regular && !self.statusItem.isVisible,"Dock-only mode")
   _=self.applicationShouldHandleReopen(NSApp,hasVisibleWindows:false)
   precondition(self.statsWindow!.window.isVisible,"Dock reopen must show Stats")
   self.sessionClock.begin(date:Date(timeIntervalSince1970:1791032400),at:BoostClock.now-90061)
   self.updateStatistics()
   let date=DateFormatter.localizedString(from:Date(timeIntervalSince1970:1791032400),dateStyle:.medium,timeStyle:.medium)
   precondition(self.statsWindow!.activity.stringValue.contains(date) && self.statsWindow!.activity.stringValue.contains("1d 1h 1m"),"Session date and multi-day runtime visible")
   precondition(self.statsWindow!.activity.stringValue.contains("App uptime:"),"App uptime visible")
   self.toggleDock();precondition(self.settings.showDock,"Cannot hide last access path")
   self.toggleMenuBar();self.toggleDock()
   precondition(NSApp.activationPolicy() == .accessory && self.statusItem.isVisible,"Menu-only mode")
   precondition(self.dockCheck.state == .off && self.menuBarCheck.state == .on,"Menu visibility changes refresh Settings controls")
   let coin=NSMenuItem();coin.representedObject="DOGE";self.switchCurrency(coin)
   precondition(self.settings.coin=="DOGE" && self.settings.address=="D5ERdEN1gsouFSs7zsq7VYJxyWP6dP28H1" && !self.enabled,"Menu switch restores matching saved wallet and stays stopped")
   precondition(self.sessionClock.startedDate==nil && self.sessionClock.uptime()>0,"A different currency starts with a fresh session and retains app uptime")
   self.showSettings();self.window!.contentView!.layoutSubtreeIfNeeded()
   if let content=self.window!.contentView,let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
    content.cacheDisplay(in:content.bounds,to:bitmap)
    try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/private/tmp/idle-miner-settings-build8.png"))
   }
   self.showStatistics();self.statsWindow!.window.contentView!.layoutSubtreeIfNeeded()
   if let content=self.statsWindow!.window.contentView,let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
    content.cacheDisplay(in:content.bounds,to:bitmap)
    try? bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/private/tmp/idle-miner-stats-build8.png"))
   }
   let original=self.engine!
   self.engine=Engine(resources:self.baseFolder.appendingPathComponent("missing-engine"),folder:self.baseFolder.appendingPathComponent("fault-logs"))
   self.startMining()
   precondition(self.fatalError != nil && !self.enabled && !self.engine.running,"Failed start remains stopped")
   let elapsed=self.sessionClock.elapsed();precondition(self.sessionClock.elapsed(at:BoostClock.now+100)==elapsed,"Failed start freezes session runtime")
   self.engine=original;self.stopMining()
   print("PASS: failed start clock, menu durations, timer expiry/cancel, centered About/byline, Stats graph/balances/freshness, synchronized login controls/approval, health colors/explanations, Settings; no mining on launch")
   print("Capture window IDs: settings=\(self.window!.windowNumber), stats=\(self.statsWindow!.window.windowNumber)");fflush(stdout)
   if ProcessInfo.processInfo.environment["IDLE_MINER_KEEP_UI"] != "1" { NSApp.terminate(nil) }
  }
 }
}
@main struct Main {
 @MainActor static func main() {
  let app=NSApplication.shared; let delegate=SmokeApp(); app.delegate=delegate; app.setActivationPolicy(.accessory)
  withExtendedLifetime(delegate) { app.run() }
 }
}
