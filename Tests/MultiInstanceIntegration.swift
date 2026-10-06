import AppKit
import ServiceManagement
import Darwin
@MainActor final class NoLoginItem:LoginItemManaging {
 var status:SMAppService.Status { .notRegistered }
 func setEnabled(_ enabled:Bool)throws {}
 func openSystemSettings() {}
}
@MainActor final class FixtureApp:MinerApp {
 var monitor:Timer?
 var started=false
 override var statisticsNetworkingEnabled:Bool { false }
 override var engineResources:URL { URL(fileURLWithPath:CommandLine.arguments.last!) }
 override func applicationDidFinishLaunching(_ note:Notification) {
  loginManager=NoLoginItem();super.applicationDidFinishLaunching(note)
  settings.idleThreads=2
  _=try? coordinator?.quota(requested:2,actual:0,budget:2,cores:16)
  print("\(profileName):BOOT");fflush(stdout)
  monitor=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in MainActor.assumeIsolated {
   guard let self=self else { return }
   if !self.started && FileManager.default.fileExists(atPath:self.baseFolder.appendingPathComponent("go").path) {
    self.started=true;let item=NSMenuItem();item.tag=2;self.startBenchmark(item)
    self.benchmarkDeadline=Date().addingTimeInterval(140)
   }
   if FileManager.default.fileExists(atPath:self.baseFolder.appendingPathComponent("stop-\(self.profileName)").path) { self.quitApp() }
   if self.fatalError != nil { print("\(self.profileName):FAULT \(self.fatalError!)");fflush(stdout);self.quitApp() }
  }}
 }
 override func readLine(_ line:String) {
  super.readLine(line)
  if line.contains("READY threads ") || line.contains("init dataset algo") { print("\(profileName):\(line)");fflush(stdout) }
 }
}
@main struct MultiInstanceIntegration {
 @MainActor static func main()throws {
  if CommandLine.arguments.contains("--worker") {
   let app=NSApplication.shared;let delegate=FixtureApp();app.delegate=delegate;app.setActivationPolicy(.accessory)
   withExtendedLifetime(delegate){app.run()};return
  }
  let folder=FileManager.default.temporaryDirectory.appendingPathComponent("miner-multi-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:folder) }
  let resources=CommandLine.arguments.last!
  var processes=[String:Process]();var outputs=[String]();var lineBuffers=[String:LineBuffer]()
  for profile in ["default","DOGE"] {
   let process=Process();let pipe=Pipe()
   process.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);process.arguments=["--worker","--profile=\(profile)",resources]
   var env=ProcessInfo.processInfo.environment;env["IDLE_MINER_STATE"]=folder.path;process.environment=env
   process.standardOutput=pipe;process.standardError=pipe
   pipe.fileHandleForReading.readabilityHandler={ handle in
    let data=handle.availableData
    if data.isEmpty { handle.readabilityHandler=nil;return }
    DispatchQueue.main.async {
     var buffer=lineBuffers[profile] ?? LineBuffer()
     for line in buffer.feed(data) { outputs.append(line);if line.contains(":BOOT") || line.contains("READY threads") || line.contains(":FAULT") { print(line) } }
     lineBuffers[profile]=buffer
    }
   }
   try process.run();processes[profile]=process
  }
  defer { for process in processes.values where process.isRunning { process.terminate() } }
  let deadline=Date().addingTimeInterval(160)
  func wait(_ predicate:()->Bool)throws {
   while !predicate() {
    if Date()>deadline || outputs.contains(where:{$0.contains(":FAULT")}) { throw MinerError.message("Multi-instance integration timed out or faulted.") }
    RunLoop.current.run(until:Date().addingTimeInterval(0.1))
   }
  }
  try wait{outputs.filter{$0.contains(":BOOT")}.count==2}
  try Data().write(to:folder.appendingPathComponent("go"))
  try wait{["default","DOGE"].allSatisfy{p in outputs.contains{$0.hasPrefix(p+":") && $0.contains("READY threads 1/1 ")}}}
  let records=(try FileManager.default.contentsOfDirectory(at:folder.appendingPathComponent("Coordination"),includingPropertiesForKeys:nil)).filter{$0.pathExtension=="json"}
  let reserved=try records.reduce(0){sum,url in sum+((try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any])["reserved"] as! Int)}
  precondition(reserved<=2,"Combined reservations exceeded configured two-thread budget")
  try Data().write(to:folder.appendingPathComponent("stop-DOGE"))
  try wait{!processes["DOGE"]!.isRunning}
  try wait{outputs.contains{$0.hasPrefix("default:") && $0.contains("READY threads 2/2 ")}}
  // Simulate controller death. Supervisor's engine lease must keep capacity
  // occupied until its own process group is stopped/reaped.
  kill(processes["default"]!.processIdentifier,SIGKILL)
  try wait{!processes["default"]!.isRunning}
  let survivor=try ProfileCoordinator(base:folder,profile:"BTC")
  var reclaimed=false
  while Date()<deadline {
   let quota=try survivor.quota(requested:2,actual:0,budget:2,cores:16)
   if quota==2 { reclaimed=true;break }
   RunLoop.current.run(until:Date().addingTimeInterval(0.1))
  }
  precondition(reclaimed,"Crash must release capacity after the owned engine is stopped")
  print("PASS: actual Mac controllers READY 1/1 + 1/1 within shared two-thread cap; survivor reloads 2/2 after peer Quit; crash reclaims supervised capacity")
 }
}
