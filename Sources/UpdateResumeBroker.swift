import AppKit

// A real application bundle lets Sparkle wait for and relaunch this broker via
// its public applicationBundle initializer. No private Sparkle hooks are used.
@MainActor enum UpdateResumeBroker {
 static let bundleName="Idle Miner Update Resume.app"
 static func bundleURL(in host:URL)->URL { host.appendingPathComponent("Contents/Helpers/\(bundleName)",isDirectory:true) }
 static func hostURL(from broker:URL)->URL { broker.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
 static var defaultBase:URL {
  if let path=ProcessInfo.processInfo.environment["IDLE_MINER_STATE"] { return URL(fileURLWithPath:path,isDirectory:true) }
  return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Idle Miner",isDirectory:true)
 }
 static func capability(in arguments:[String])->UUID? {
  arguments.first(where:{$0.hasPrefix("--update-resume=")}).flatMap{UUID(uuidString:String($0.dropFirst("--update-resume=".count)))}
 }
 static func run(hostURL:URL,base:URL) {
  let controllerPID=CommandLine.arguments.first(where:{$0.hasPrefix("--wait-for-controller=")}).flatMap{Int32($0.dropFirst("--wait-for-controller=".count))}
  let app=NSApplication.shared
  let delegate=UpdateResumeBrokerDelegate(hostURL:hostURL,base:base,controllerPID:controllerPID)
  app.delegate=delegate;app.setActivationPolicy(.accessory)
  withExtendedLifetime(delegate) { app.run() }
 }
}

@MainActor private final class UpdateResumeBrokerDelegate:NSObject,NSApplicationDelegate {
 private let host:URL
 private let base:URL
 private let store:UpdateResumeStore
 private let controllerPID:Int32?
 private var controller:NSRunningApplication?
 private var processMonitor:DispatchSourceProcess?
 private var controllerExited=false
 private var hasControllerExited:Bool { controllerExited || controller?.isTerminated==true }
 private var timer:Timer?
 private var terminating=false
 private var deadline=ContinuousClock.now
 private var capability:UUID?
 private var leases=[FileLease]()
 init(hostURL:URL,base:URL,controllerPID:Int32?) {
  host=hostURL.resolvingSymlinksInPath().standardizedFileURL;self.base=base;store=UpdateResumeStore(base:base);self.controllerPID=controllerPID
 }
 private func hostInfo()->[String:Any]? {
  // Read the installed file afresh after replacement; Bundle caches by URL.
  guard let bytes=try? Data(contentsOf:host.appendingPathComponent("Contents/Info.plist")) else { return nil }
  return (try? PropertyListSerialization.propertyList(from:bytes,format:nil)) as? [String:Any]
 }
 func applicationDidFinishLaunching(_ notification:Notification) {
  if let pid=controllerPID {
   guard let application=NSRunningApplication(processIdentifier:pid),application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL==host else { NSApp.terminate(nil);return }
   controller=application
   let monitor=DispatchSource.makeProcessSource(identifier:pid,eventMask:.exit,queue:.main)
   monitor.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.controllerExited=true;self?.pollController() } }
   monitor.resume();processMonitor=monitor
   return
  }
  // Sparkle reopens the newly installed broker, which alone supplies a fresh
  // explicit capability. Ordinary launches of the host carry no such argument.
  guard let info=hostInfo(),let build=info["CFBundleVersion"] as? String,let version=info["CFBundleShortVersionString"] as? String,
        let token=try? store.relaunchCapability(bundleURL:host,build:build,version:version) else { NSApp.terminate(nil);return }
  capability=token
  let config=NSWorkspace.OpenConfiguration();config.createsNewApplicationInstance=true;config.activates=false
  config.arguments=["--update-resume=\(token.uuidString)"]
  NSWorkspace.shared.openApplication(at:host,configuration:config) { [weak self] _,error in
   DispatchQueue.main.async {
    if error != nil { try? self?.store.discard(capability:token) }
    NSApp.terminate(nil)
   }
  }
 }
 private func pollController() {
  if !terminating {
   if hasControllerExited { NSApp.terminate(nil) }
   return
  }
  if hasControllerExited {
   do {
    var held=[FileLease]()
    for profile in ["default"]+Settings.coins { held.append(try FileLease(url:base.appendingPathComponent("Coordination/engine-\(profile).lock"))) }
    leases=held;timer?.invalidate();NSApp.reply(toApplicationShouldTerminate:true);return
   } catch { /* A supervised worker may still be finishing. */ }
  }
  if ContinuousClock.now>=deadline {
   if let capability { try? store.discard(capability:capability) }
   terminating=false;NSApp.reply(toApplicationShouldTerminate:false)
  }
 }
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
  guard let pid=controllerPID else { return .terminateNow }
  if terminating { return .terminateLater }
  guard let build=hostInfo()?["CFBundleVersion"] as? String,
        let token=try? store.controllerCapability(bundleURL:host,sourceBuild:build,pid:pid) else {
   // Cancellation and errors disarm before closing the broker. They must never
   // send a quit request to the still usable host application.
   timer?.invalidate();return .terminateNow
  }
  capability=token;terminating=true;deadline=ContinuousClock.now.advanced(by:.seconds(30))
  let clock=Timer(timeInterval:0.1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.pollController() } }
  RunLoop.main.add(clock,forMode:.common);timer=clock
  if !hasControllerExited { _=controller?.terminate() }
  return .terminateLater
 }
}
