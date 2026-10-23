import AppKit
import ServiceManagement
@MainActor final class StartupLogin:LoginItemManaging {
 var status:SMAppService.Status = .enabled
 var launchedAtLogin=true
 func setEnabled(_ enabled:Bool)throws {}
 func openSystemSettings() {}
}
@MainActor final class LoginStartupApp:MinerApp {
 var starts=0
 var opened=[String:[String]]()
 override var statisticsNetworkingEnabled:Bool { false }
 override func startMining() { starts += 1 }
 override func alert(_ text:String) { print("FAIL: unexpected alert \(text)");exit(1) }
 override func applicationDidFinishLaunching(_ note:Notification) {
  let login=StartupLogin();login.launchedAtLogin = !CommandLine.arguments.contains("--manual")
  loginManager=login
  profileLaunchHandler={ coin,args in self.opened[coin]=args }
  super.applicationDidFinishLaunching(note)
  if login.launchedAtLogin {
   precondition(starts==1 && settings.coin=="BTC","actual controller starts selected configured coin")
   precondition(Set(opened.keys)==Set(["LTC","DOGE","ETH"]),"all remaining saved wallets opened once")
   for (coin,args) in opened { precondition(args==["--profile=\(coin)","--start-mining"],"children mine without recursive login or Stats flags") }
  } else { precondition(starts==0 && opened.isEmpty,"manual launch must not use saved login consent") }
  let event=NSAppleEventDescriptor(eventClass:kCoreEventClass,eventID:kAEOpenApplication,targetDescriptor:nil,returnID:AEReturnID(kAutoGenerateReturnID),transactionID:AETransactionID(kAnyTransactionID))
  precondition(!SystemLoginItem.isLoginEvent(event),"ordinary launch event is not a login")
  event.setParam(NSAppleEventDescriptor(enumCode:keyAELaunchedAsLogInItem),forKeyword:keyAEPropData)
  precondition(SystemLoginItem.isLoginEvent(event),"system login marker recognized")
  precondition(!SystemLoginItem.isLoginEvent(nil),"missing event cannot auto-mine")
  print("PASS: native controller \(login.launchedAtLogin ? "login" : "manual") startup, four-currency orchestration, and Apple event recognition")
  timer?.invalidate();statusItem.isVisible=false;coordinator=nil;exit(0)
 }
}
@main struct LoginStartupIntegration {
 @MainActor static func main()throws {
  let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["IDLE_MINER_STATE"]!)
  var settings=Settings();settings.coin="BTC";settings.address="1BoatSLRHtKNngkdXEeobR76b53LETtpyT"
  settings.wallets=["BTC":settings.address,"LTC":"LKKHMBjCU89fyFNgSRprDoD8Jb25N8uWvd","DOGE":"D5ERdEN1gsouFSs7zsq7VYJxyWP6dP28H1","ETH":"0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"]
  try settings.save(to:root.appendingPathComponent("settings.json"),startMiningAtLoginChange:true)
  let app=NSApplication.shared;let delegate=LoginStartupApp();app.delegate=delegate;app.setActivationPolicy(.accessory)
  withExtendedLifetime(delegate){app.run()}
 }
}
