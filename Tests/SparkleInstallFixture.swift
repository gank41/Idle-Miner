import AppKit
import CryptoKit
import Sparkle
import Darwin

// Standalone test app only. Its bundle ID, signing key, feed, state and worker
// are unique fixtures; this executable never links MinerApp or the mining engine.
@MainActor final class SparkleFixtureApp:NSObject,NSApplicationDelegate,SPUUpdaterDelegate {
 private var updater:SPUUpdater?
 private var driver:UpdateUserDriver?
 private var coordinator:UpdateInstallationCoordinator?
 private var worker:Process?
 private var profileCoordinator:ProfileCoordinator?
 private var broker:NSRunningApplication?
 private var profile:String { CommandLine.arguments.contains("--fixture-peer") ? ProfileCoordinator.profileArgument(CommandLine.arguments):"DOGE" }
 private var fixtureCoin:String { CommandLine.arguments.first(where:{$0.hasPrefix("--fixture-coin=")}).map{String($0.dropFirst(15))} ?? "ETH" }
 private var fixtureEnabled:Bool { !CommandLine.arguments.contains("--fixture-stopped") }
 private var timer:Timer?
 private var clicked=false
 private var completed=false
 private var cancelled=false
 private var cancelsUpdate:Bool { Bundle.main.object(forInfoDictionaryKey:"FixtureCancelUpdate") as? Bool == true }
 private let started=ContinuousClock.now
 static var reportURL:URL { URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"FixtureReportPath") as! String) }
 static var stateURL:URL { URL(fileURLWithPath:Bundle.main.object(forInfoDictionaryKey:"FixtureStatePath") as! String) }
 static func report(_ event:String,_ extra:[String:Any]=[:]) {
  var record=extra;record["event"]=event;record["pid"]=getpid();record["build"]=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "";record["path"]=Bundle.main.bundleURL.path
  let data=(try! JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]))+Data([10])
  let fd=open(reportURL.path,O_WRONLY|O_CREAT|O_APPEND|O_CLOEXEC,0o600)
  guard fd>=0 else { return };defer { close(fd) }
  data.withUnsafeBytes { ptr in _=write(fd,ptr.baseAddress,data.count) }
 }
 func applicationDidFinishLaunching(_ notification:Notification) {
  let event=NSAppleEventManager.shared().currentAppleEvent
  Self.report("launched",["arguments":CommandLine.arguments,"frameworkPath":Bundle(for:SPUUpdater.self).bundleURL.path,"appleEvent":event?.description ?? "nil","senderPID":event?.attributeDescriptor(forKeyword:keySenderPIDAttr)?.int32Value ?? -1,"parentPID":getppid()])
  if Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String == "2" {
   let resume=try? UpdateResumeStore(base:Self.stateURL).consume(bundleURL:Bundle.main.bundleURL,build:"2",version:"1.0",loginLaunch:false,capability:UpdateResumeBroker.capability(in:CommandLine.arguments))
   let replay=try? UpdateResumeStore(base:Self.stateURL).consume(bundleURL:Bundle.main.bundleURL,build:"2",version:"1.0",loginLaunch:false)
   Self.report("relaunched",["resumed":resume?.currencies ?? [:],"primary":resume?.primaryCoin ?? "missing","replayed":replay != nil,"wallet":(try? String(contentsOf:Self.stateURL.appendingPathComponent("fake-wallet.txt"),encoding:.utf8)) ?? "missing"])
   DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { NSApp.terminate(nil) };return
  }
  do { profileCoordinator=try ProfileCoordinator(base:Self.stateURL,profile:profile) }
  catch { Self.report("fixture-error",["message":error.localizedDescription]);NSApp.terminate(nil);return }
  if CommandLine.arguments.contains("--fixture-peer") {
   Self.report("peer-ready",["coin":fixtureCoin,"enabled":fixtureEnabled])
   try? Data().write(to:Self.stateURL.appendingPathComponent("peer-ready-\(profile)"));return
  }
  Task { await begin() }
 }
 private func begin() async {
  do {
   let coordination=UpdateInstallationCoordinator(base:Self.stateURL);try coordination.beginCycle();coordinator=coordination
   for (slot,coin,enabled) in [("default","LTC",false),("BTC","BTC",false),("ETH","DOGE",true)] {
    let config=NSWorkspace.OpenConfiguration();config.createsNewApplicationInstance=true;config.activates=false
    config.arguments=["--fixture-peer","--profile=\(slot)","--fixture-coin=\(coin)"]+(enabled ? []:["--fixture-stopped"])
    let peer=try await NSWorkspace.shared.openApplication(at:Bundle.main.bundleURL,configuration:config)
    Self.report("peer-opened",["peerPID":peer.processIdentifier])
   }
   let peerDeadline=ContinuousClock.now.advanced(by:.seconds(10))
   while !["default","BTC","ETH"].allSatisfy({FileManager.default.fileExists(atPath:Self.stateURL.appendingPathComponent("peer-ready-\($0)").path)}) {
    guard ContinuousClock.now<peerDeadline else { throw MinerError.message("Fixture peers did not start") }
    try await Task.sleep(for:.milliseconds(20))
   }
   let process=Process();process.executableURL=Bundle.main.executableURL;process.arguments=["--fixture-worker"]
   try process.run();worker=process
   // Wait for the independent fixture worker to acquire the same FileLease a
   // supervised mining worker would hold. This performs no hashing or network.
   let workerMarker=Self.stateURL.appendingPathComponent("worker-ready")
   let deadline=ContinuousClock.now.advanced(by:.seconds(10))
   while !FileManager.default.fileExists(atPath:workerMarker.path) {
    guard ContinuousClock.now<deadline else { throw MinerError.message("Fixture worker did not start") }
    try await Task.sleep(for:.milliseconds(20))
   }
   let custom=UpdateUserDriver(installedVersion:"1.0 (1)")
   custom.prepareForInstallation={ [weak self] in
    guard let self else { throw MinerError.message("Fixture disappeared") }
    Self.report("preparing",["peerCount":coordination.matchingPeers().count,"workerRunning":self.worker?.isRunning ?? false])
    guard let item=custom.selectedUpdate else { throw MinerError.message("Missing fixture update") }
    try coordination.captureResume(profile:self.profile,coin:self.fixtureCoin,enabled:self.fixtureEnabled,targetBuild:item.versionString,targetVersion:item.displayVersionString)
    try await coordination.prepare(timeout:15,stop:{self.worker?.terminate()},isEngineRunning:{self.worker?.isRunning ?? false})
    try coordination.finalizeResume()
    var held=0
    for profile in ["default"]+Settings.coins {
     do { _=try FileLease(url:Self.stateURL.appendingPathComponent("Coordination/engine-\(profile).lock")) }
     catch { held += 1 }
    }
    Self.report("prepared",["remainingPeers":coordination.matchingPeers().count,"workerRunning":self.worker?.isRunning ?? false,"retainedWorkerLeases":held])
   }
   custom.installationFailed={ [weak self] in coordination.endCycle(discardResume:true);_=self?.broker?.terminate() }
   driver=custom
   let brokerURL=UpdateResumeBroker.bundleURL(in:Bundle.main.bundleURL)
   let config=NSWorkspace.OpenConfiguration();config.createsNewApplicationInstance=true;config.activates=false;config.arguments=["--wait-for-controller=\(getpid())"]
   broker=try await NSWorkspace.shared.openApplication(at:brokerURL,configuration:config)
   Self.report("broker-opened",["peerPID":broker!.processIdentifier])
   let controller=SPUUpdater(hostBundle:Bundle.main,applicationBundle:Bundle(url:brokerURL)!,userDriver:custom,delegate:self)
   controller.automaticallyChecksForUpdates=false;controller.automaticallyDownloadsUpdates=false;controller.sendsSystemProfile=false
   try controller.start();updater=controller
   timer=Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
   controller.checkForUpdates()
  } catch { Self.report("fixture-error",["message":error.localizedDescription]);NSApp.terminate(nil) }
 }
 private func views(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(views) }
 private func poll() {
  guard !completed else { return }
  if cancelled,broker?.isTerminated==true {
   completed=true
   Self.report("cancelled",["workerRunning":worker?.isRunning ?? false,"remainingPeers":coordinator?.matchingPeers().count ?? -1])
   DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { NSApp.terminate(nil) };return
  }
  if ContinuousClock.now-started > .seconds(95) {
   completed=true;Self.report("fixture-error",["message":"Sparkle fixture exceeded its bounded timeout"]);NSApp.terminate(nil);return
  }
  guard let driver,let content=driver.updateWindow?.contentView else { return }
  let all=views(content)
  if driver.state.phase == .available && !clicked {
   clicked=true
   let button=all.compactMap{$0 as? NSButton}.first{$0.accessibilityIdentifier()=="update-install-now"}!
   Self.report("offered",["installed":driver.state.installedVersion,"latest":driver.state.latestVersion ?? "","button":button.title,"notes":all.compactMap{$0 as? NSTextView}.first?.string ?? ""])
   if cancelsUpdate { all.compactMap{$0 as? NSButton}.first{$0.title=="Close"}!.performClick(nil) }
   else { button.performClick(nil) }
  }
  if driver.state.phase == .finished {
   // An error must close the disarmed broker while leaving this controller
   // alive. Only the fixture's later explicit Quit may terminate it.
   if let broker,!broker.isTerminated { return }
   completed=true
   let message=all.compactMap{$0 as? NSTextField}.first{$0.accessibilityIdentifier()=="update-status"}?.stringValue ?? ""
   Self.report("rejected",["message":message,"clicked":clicked])
   all.compactMap{$0 as? NSButton}.first{$0.title=="Close"}?.performClick(nil)
   DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { NSApp.terminate(nil) }
  }
 }
 func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
  try? UpdateResumeStore(base:Self.stateURL).acknowledge(bundleURL:Bundle.main.bundleURL,sourceBuild:"1",profile:profile,pid:getpid(),coin:fixtureCoin,enabled:fixtureEnabled)
  Self.report(CommandLine.arguments.contains("--fixture-peer") ? "peer-terminated":"terminating")
  worker?.terminate();timer?.invalidate()
  return .terminateNow
 }
 func updaterWillRelaunchApplication(_ updater:SPUUpdater) {
  do { try coordinator?.armResume();Self.report("resume-armed") }
  catch { Self.report("fixture-error",["message":error.localizedDescription]) }
 }
 func updaterShouldPromptForPermissionToCheck(forUpdates updater:SPUUpdater)->Bool { false }
 func updater(_ updater:SPUUpdater,shouldDownloadReleaseNotesForUpdate item:SUAppcastItem)->Bool { false }
 func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor check:SPUUpdateCheck,error:Error?) {
  Self.report("cycle-ended",["error":error?.localizedDescription ?? ""])
  let armed=coordinator?.hasArmedResume ?? false
  coordinator?.endCycle(discardResume:error != nil)
  if error != nil || !armed { _=broker?.terminate() }
  if cancelsUpdate && error==nil { cancelled=true }
 }
}

@main struct SparkleInstallFixture {
 @MainActor static func main() throws {
  if Bundle.main.bundleIdentifier?.hasSuffix(".broker")==true {
   let host=UpdateResumeBroker.hostURL(from:Bundle.main.bundleURL)
   let state=URL(fileURLWithPath:Bundle(url:host)!.object(forInfoDictionaryKey:"FixtureStatePath") as! String)
   UpdateResumeBroker.run(hostURL:host,base:state);return
  }
  if CommandLine.arguments.count==4 && CommandLine.arguments[1]=="--generate-key" {
   let key=Curve25519.Signing.PrivateKey()
   let privateURL=URL(fileURLWithPath:CommandLine.arguments[2]);let publicURL=URL(fileURLWithPath:CommandLine.arguments[3])
   try Data(key.rawRepresentation.base64EncodedString().utf8).write(to:privateURL,options:.withoutOverwriting)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:privateURL.path)
   try Data(key.publicKey.rawRepresentation.base64EncodedString().utf8).write(to:publicURL)
   return
  }
  if CommandLine.arguments.contains("--fixture-worker") {
   let lease=try FileLease(url:SparkleFixtureApp.stateURL.appendingPathComponent("Coordination/engine-default.lock"))
   signal(SIGTERM) { _ in _exit(0) }
   SparkleFixtureApp.report("worker-ready")
   try Data().write(to:SparkleFixtureApp.stateURL.appendingPathComponent("worker-ready"))
   withExtendedLifetime(lease) { while true { pause() } }
   return
  }
  let app=NSApplication.shared
  let delegate=SparkleFixtureApp();app.delegate=delegate;app.setActivationPolicy(.accessory)
  withExtendedLifetime(delegate) { app.run() }
 }
}
