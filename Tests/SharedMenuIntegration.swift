import AppKit
import ServiceManagement
import Darwin

// Native controller/menu fixtures: no real wallet, mining, or network request.
@MainActor private final class SharedMenuFixtureLogin:LoginItemManaging {
 var status:SMAppService.Status { .notRegistered }
 var launchedAtLogin:Bool { false }
 func setEnabled(_ enabled:Bool)throws {}
 func openSystemSettings() {}
}
@MainActor private final class SharedMenuFixtureApp:MinerApp {
 var monitor:Timer?
 var statsCalls=0
 var handled=0
 var launches=[[String]]()
 var failure:String?
 override var statisticsNetworkingEnabled:Bool { false }
 override var engineResources:URL { baseFolder.appendingPathComponent("no-engine-fixture") }
 var reportURL:URL { baseFolder.appendingPathComponent("integration-report-\(profileName).json") }
 var directiveURL:URL { baseFolder.appendingPathComponent("integration-directive-\(profileName).txt") }
 override func applicationDidFinishLaunching(_ note:Notification) {
  loginManager=SharedMenuFixtureLogin()
  profileLaunchHandler={ [weak self] _,arguments in self?.launches.append(arguments) }
  super.applicationDidFinishLaunching(note)
  timer?.invalidate();timer=nil
  monitor=Timer(timeInterval:0.1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.monitorStep() } }
  RunLoop.main.add(monitor!,forMode:.common);monitorStep()
 }
 func publishFixture() {
  guard statusItem != nil,profileMenu != nil else { return }
  let level=profileName=="BTC" ? "working" : profileName=="DOGE" ? "issue" : "inactive"
  let lines=["TEST FIXTURE · \(settings.coin)","TEST FIXTURE · \(level)","No engine or network used","No real mining work","No real price","No real balance"]
  menuSummary.update(lines);refreshSharedMenu(level:level,lines:lines)
 }
 override func showStatistics() { statsCalls += 1;super.showStatistics() }
 override func alert(_ text:String) { failure=text }
 func monitorStep() {
  drainSharedMenuCommands()
  guard !quitting else { return }
  if let directive=try? String(contentsOf:directiveURL,encoding:.utf8) {
   try? FileManager.default.removeItem(at:directiveURL);handled += 1
   if directive=="quit" { quitApp();return }
   let parts=directive.split(separator:":").map(String.init)
   if parts.count==2,parts[0]=="stats" {
    if let item=sharedCurrencyRows[parts[1]]?.submenu?.items.first(where:{$0.title=="Mining Stats…"}),let action=item.action {
     if !NSApp.sendAction(action,to:item.target,from:item) { failure="Could not send native Stats action" }
    } else { failure="Missing currency Stats action" }
   } else if parts.count==2,parts[0]=="switch" {
    let item=NSMenuItem();item.representedObject=parts[1];switchCurrency(item)
   } else { failure="Unknown integration directive" }
  }
  publishFixture()
  let colors=sharedCurrencyRows.mapValues { row -> String in
   let value=row.attributedTitle?.attribute(.foregroundColor,at:0,effectiveRange:nil) as? NSColor
   return value == .systemGreen ? "green" : value == .systemRed ? "red" : value == .systemGray ? "gray" : "unknown"
  }
  let rows=unifiedMenu?.items.prefix(4).map(\.title) ?? []
  let submenus=unifiedMenu?.items.prefix(4).allSatisfy{$0.submenu != nil && $0.view==nil} ?? false
  let report:[String:Any]=["profile":profileName,"coin":settings.coin,"owner":sharedMenuStore?.ownsMenu ?? false,"visible":statusItem.isVisible,"glyph":statusItem.button?.title ?? "","rows":rows,"submenus":submenus,"colors":colors,"statsCalls":statsCalls,"statsVisible":statsWindow?.window.isVisible ?? false,"enabled":enabled,"engineRunning":engine.running,"handled":handled,"launches":launches,"failure":failure ?? ""]
  do { try JSONSerialization.data(withJSONObject:report,options:.sortedKeys).write(to:reportURL,options:.atomic) }
  catch { fputs("Could not write fixture report: \(error)\n",stderr);exit(1) }
 }
}
@main struct SharedMenuIntegration {
 @MainActor static func main()throws {
  if CommandLine.arguments.contains("--worker") {
   let app=NSApplication.shared,delegate=SharedMenuFixtureApp()
   app.delegate=delegate;app.setActivationPolicy(.accessory)
   withExtendedLifetime(delegate) { app.run() };return
  }
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("miner-native-shared-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  let profiles=["default","BTC","DOGE","ETH"]
  var processes=[String:Process]()
  func directive(_ profile:String,_ action:String)throws {
   try Data(action.utf8).write(to:root.appendingPathComponent("integration-directive-\(profile).txt"),options:.atomic)
  }
  defer {
   // Only these test children are stopped; normal exit and cleanup are bounded.
   for (profile,process) in processes where process.isRunning { try? directive(profile,"quit") }
   let deadline=Date().addingTimeInterval(4)
   while processes.values.contains(where:{$0.isRunning}) && Date()<deadline { Thread.sleep(forTimeInterval:0.05) }
   for process in processes.values where process.isRunning { process.terminate() }
   let terminateDeadline=Date().addingTimeInterval(2)
   while processes.values.contains(where:{$0.isRunning}) && Date()<terminateDeadline { Thread.sleep(forTimeInterval:0.05) }
   for process in processes.values where process.isRunning { kill(process.processIdentifier,SIGKILL) }
   for process in processes.values { process.waitUntilExit() }
   try? FileManager.default.removeItem(at:root)
  }
  func report(_ profile:String)->[String:Any]? {
   guard let data=try? Data(contentsOf:root.appendingPathComponent("integration-report-\(profile).json")) else { return nil }
   return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
  }
  func wait(_ description:String,timeout:TimeInterval=12,_ predicate:()->Bool)throws {
   let end=Date().addingTimeInterval(timeout)
   while !predicate() {
    if Date()>end { throw MinerError.message("Native shared-menu integration timed out: \(description). Reports: \(profiles.compactMap { report($0) })") }
    for (profile,process) in processes where process.isRunning {
     if let failure=report(profile)?["failure"] as? String,!failure.isEmpty { throw MinerError.message("\(profile): \(failure)") }
    }
    Thread.sleep(forTimeInterval:0.05)
   }
  }
  func launch(_ profile:String)throws {
   let process=Process();process.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
   process.arguments=["--worker","--profile=\(profile)"]
   var environment=ProcessInfo.processInfo.environment;environment["IDLE_MINER_STATE"]=root.path;process.environment=environment
   process.standardOutput=FileHandle.nullDevice;process.standardError=FileHandle.standardError
   try process.run();processes[profile]=process
  }
  try launch("default");try wait("initial owner") { report("default")?["owner"] as? Bool == true }
  for profile in profiles.dropFirst() { try launch(profile) }
  let names=["BTC":"Bitcoin (BTC)","LTC":"Litecoin (LTC)","DOGE":"Dogecoin (DOGE)","ETH":"Ethereum (ETH)"]
  let expectedRows=Settings.coins.map { names[$0]! }
  let expectedColors=["BTC":"green","LTC":"gray","DOGE":"red","ETH":"gray"]
  try wait("one visible native icon and four currency submenus") {
   let reports=profiles.compactMap(report)
   return reports.count==4 && reports.filter{$0["owner"] as? Bool == true}.count==1 && reports.filter{$0["visible"] as? Bool == true}.count==1 && report("default")?["rows"] as? [String] == expectedRows && report("default")?["colors"] as? [String:String] == expectedColors && report("default")?["submenus"] as? Bool == true
  }
  guard profiles.allSatisfy({report($0)?["glyph"] as? String == "₿" && report($0)?["enabled"] as? Bool == false && report($0)?["engineRunning"] as? Bool == false}) else { throw MinerError.message("Fixture started mining or changed the single-glyph icon") }
  try directive("default","stats:ETH")
  try wait("remote Stats reaches intended ETH controller") { report("ETH")?["statsCalls"] as? Int == 1 && report("ETH")?["statsVisible"] as? Bool == true }
  guard profiles.filter({$0 != "ETH"}).allSatisfy({report($0)?["statsCalls"] as? Int == 0}) else { throw MinerError.message("Remote Stats reached the wrong controller") }
  // BTC's named process slot now holds DOGE. Missing BTC must use a free slot.
  try directive("BTC","switch:DOGE")
  try wait("switched profile removes old payout currency") { report("BTC")?["coin"] as? String == "DOGE" && report("default")?["colors"] as? [String:String] == ["BTC":"gray","LTC":"gray","DOGE":"green","ETH":"gray"] }
  try directive("default","stats:BTC")
  try wait("missing BTC routes through a free profile slot") { (report("default")?["launches"] as? [[String]])?.last?.contains("--currency=BTC") == true }
  guard let launch=(report("default")?["launches"] as? [[String]])?.last,launch.contains("--profile=LTC"),launch.contains("--show-stats"),!launch.contains("--start-mining") else { throw MinerError.message("Missing-currency Stats lost currency or stopped launch semantics") }
  try directive("default","quit");try wait("owner exits gracefully") { processes["default"]?.isRunning == false }
  try wait("surviving controller takes presentation lease") {
   let reports=profiles.dropFirst().compactMap(report)
   return reports.filter{$0["owner"] as? Bool == true}.count==1 && reports.filter{$0["visible"] as? Bool == true}.count==1
  }
  guard profiles.dropFirst().allSatisfy({processes[$0]?.isRunning == true && report($0)?["enabled"] as? Bool == false && report($0)?["engineRunning"] as? Bool == false}) else { throw MinerError.message("Owner handover changed worker lifetime or started mining") }
  print("PASS: four separate native Mac controllers; one ₿ icon/lease; four colored currency submenus; targeted remote Stats; switched-profile routing; graceful owner handover; no mining or network")
 }
}
