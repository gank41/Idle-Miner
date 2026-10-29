import AppKit
import ServiceManagement

@MainActor final class ResumeLogin:LoginItemManaging {
 let status:SMAppService.Status = .enabled
 var launchedAtLogin:Bool { CommandLine.arguments.contains("--login") }
 func setEnabled(_ enabled:Bool)throws {}
 func openSystemSettings() {}
}
@MainActor final class ResumeStartupApp:MinerApp {
 var fixtureEnvironment=Environment()
 var opened=[String:[String]]()
 override var statisticsNetworkingEnabled:Bool { false }
 override func environmentSample()->Environment { fixtureEnvironment }
 override func alert(_ text:String) { Swift.fatalError("Unexpected alert: \(text)") }
 override func applicationDidFinishLaunching(_ notification:Notification) {
  loginManager=ResumeLogin()
  profileLaunchHandler={coin,args in self.opened[coin]=args}
  fixtureEnvironment.memoryPressure=true
  let before=try! Data(contentsOf:settingsURL)
  super.applicationDidFinishLaunching(notification)
  let scenario=CommandLine.arguments.contains("--login") ? (settings.startMiningAtLogin ? "login-on":"login-off") : CommandLine.arguments.contains("--manual") ? "manual":"update"
  switch scenario {
  case "update":
   precondition(settings.coin=="ETH" && enabled,"update restores named updater's switched currency intent")
   precondition(Set(opened.keys)==Set(["LTC","DOGE","BTC"]),"all currencies reopen")
   precondition(opened["DOGE"]?.contains("--start-mining")==true,"enabled peer resumes")
   precondition(opened["BTC"]?.contains("--start-mining")==false && opened["LTC"]?.contains("--start-mining")==false,"stopped peers remain stopped")
  case "login-on":
   precondition(settings.coin=="BTC" && enabled,"actual login applies configured login plan")
   precondition(Set(opened.keys)==Set(["LTC","DOGE","ETH"]) && opened.values.allSatisfy{$0.contains("--start-mining")},"login-on starts all configured currencies")
  default: precondition(!enabled && opened.isEmpty,"login-off/manual stays stopped")
  }
  if enabled {
   precondition(!engine.running && desiredThreads==0 && boost==nil && benchmarkDeadline==nil,"resume returns to automatic mode under memory safety guard")
   var samples=[Environment]()
   var active=Environment();active.idleSeconds=0;samples.append(active)
   var hot=Environment();hot.thermal=2;samples.append(hot)
   var battery=Environment();battery.onAC=false;samples.append(battery)
   var asleep=Environment();asleep.sleeping=true;samples.append(asleep)
   for sample in samples {
    fixtureEnvironment=sample;tick()
    precondition(enabled && !engine.running && desiredThreads==0,"ordinary idle, heat, battery and sleep guards remain authoritative")
   }
  }
  precondition(try! Data(contentsOf:settingsURL)==before,"startup preserves saved wallets and preferences")
  precondition(!FileManager.default.fileExists(atPath:baseFolder.appendingPathComponent("UpdateResume/receipt.json").path),"receipt consumed or discarded exactly once")
  let handoff=UpdateResumeStore(base:baseFolder)
  try! handoff.begin(bundleURL:Bundle.main.bundleURL,sourceBuild:"13",targetBuild:"14",targetVersion:"1.9.2",primaryProfile:profileName,expected:[profileName:getpid()])
  stopMining();precondition(!automaticMiningIntent,"manually stopped session has no automatic intent")
  pendingRestart=true;enabled=false
  precondition(automaticMiningIntent,"currency switch retains automatic intent while old worker exits")
  _=applicationShouldTerminate(NSApp)
  try! handoff.finalize();let token=try! handoff.arm()
  let switchingPlan=try! handoff.consume(bundleURL:Bundle.main.bundleURL,build:"14",version:"1.9.2",loginLaunch:false,capability:token)
  precondition(switchingPlan?.currencies[settings.coin]==true,"termination captures pending switched-currency restart before clearing state")
  print("PASS: real MinerApp \(scenario) startup, currency restoration, stopped peers, login precedence, Automatic safety guards and settings preservation")
  timer?.invalidate();statusItem.isVisible=false;coordinator=nil;exit(0)
 }
}
@main struct UpdateResumeStartupIntegration {
 @MainActor static func main()throws {
  let base=URL(fileURLWithPath:ProcessInfo.processInfo.environment["IDLE_MINER_STATE"]!)
  if CommandLine.arguments.contains("--fixture-prepare") {
  var settings=Settings();settings.coin="BTC";settings.address="1BoatSLRHtKNngkdXEeobR76b53LETtpyT";settings.pauseWhileActive=true
  settings.wallets=["BTC":settings.address,"LTC":"LKKHMBjCU89fyFNgSRprDoD8Jb25N8uWvd","DOGE":"D5ERdEN1gsouFSs7zsq7VYJxyWP6dP28H1","ETH":"0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"]
  try settings.save(to:base.appendingPathComponent("settings.json"),startMiningAtLoginChange:!CommandLine.arguments.contains("--login-off"))
  if !CommandLine.arguments.contains("--manual") || CommandLine.arguments.contains("--fixture-armed") {
   let store=UpdateResumeStore(base:base)
   try store.begin(bundleURL:Bundle.main.bundleURL,sourceBuild:"12",targetBuild:"13",targetVersion:"1.9.1",primaryProfile:"DOGE",expected:["DOGE":11,"BTC":12,"ETH":13,"default":14])
   for (profile,pid,coin,enabled) in [("DOGE",Int32(11),"ETH",true),("BTC",12,"BTC",false),("ETH",13,"DOGE",true),("default",14,"LTC",false)] {
    try store.acknowledge(bundleURL:Bundle.main.bundleURL,sourceBuild:"12",profile:profile,pid:pid,coin:coin,enabled:enabled)
   }
   try store.finalize();let token=try store.arm();print(token.uuidString)
  }
  return
  }
  let app=NSApplication.shared;let delegate=ResumeStartupApp();app.delegate=delegate;app.setActivationPolicy(.accessory)
  withExtendedLifetime(delegate){app.run()}
 }
}
