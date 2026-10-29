import AppKit

struct UpdatePresentationState {
 enum Phase { case checking,available,downloading,extracting,preparing,installing,finished }
 let installedVersion:String
 var latestVersion:String?
 var phase:Phase = .checking
 var installButtonTitle:String? { phase == .available ? "Download and Install Now":nil }
 var canClose:Bool { phase != .extracting && phase != .preparing && phase != .installing }
}

enum UpdateReleaseNotes {
 // This text is placed in NSTextView.string. Never invoke WebKit or an HTML
 // importer: even an image or stylesheet in release notes must not make requests.
 static func plainText(_ input:String)->String {
  var text=String(input.prefix(262_144))
  text=text.replacingOccurrences(of:"(?is)<(script|style|iframe|object)[^>]*>.*?</\\1\\s*>",with:"",options:.regularExpression)
  text=text.replacingOccurrences(of:"(?i)<(?:br\\s*/?|/p|/div|/h[1-6]|/li)\\s*>",with:"\n",options:.regularExpression)
  text=text.replacingOccurrences(of:"<[^>]*>",with:"",options:.regularExpression)
  for (entity,value) in [("&lt;","<"),("&gt;",">"),("&quot;","\""),("&#39;","'"),("&apos;","'"),("&nbsp;"," "),("&amp;","&")] {
   text=text.replacingOccurrences(of:entity,with:value)
  }
  return text.trimmingCharacters(in:.whitespacesAndNewlines)
 }
}

@MainActor final class UpdateInstallationCoordinator {
 private let base:URL
 private var updateLease:FileLease?
 private var engineLeases=[FileLease]()
 private(set) var isPreparing=false
 init(base:URL) { self.base=base }
 static func matches(bundleURL:URL?,bundleIdentifier:String?,hostURL:URL,hostIdentifier:String?)->Bool {
  guard let bundleURL,let hostIdentifier,!hostIdentifier.isEmpty,bundleIdentifier==hostIdentifier else { return false }
  return bundleURL.resolvingSymlinksInPath().standardizedFileURL == hostURL.resolvingSymlinksInPath().standardizedFileURL
 }
 func beginCycle()throws {
  guard updateLease==nil else { return }
  let directory=base.appendingPathComponent("Coordination",isDirectory:true)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  do { updateLease=try FileLease(url:directory.appendingPathComponent("update.lock")) }
  catch { throw MinerError.message("Another Idle Miner window is checking or installing an update. Finish or close that update window first.") }
 }
 func endCycle() { engineLeases.removeAll();updateLease=nil;isPreparing=false }
 func matchingPeers()->[NSRunningApplication] {
  NSWorkspace.shared.runningApplications.filter {
   $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated && Self.matches(bundleURL:$0.bundleURL,bundleIdentifier:$0.bundleIdentifier,hostURL:Bundle.main.bundleURL,hostIdentifier:Bundle.main.bundleIdentifier)
  }
 }
 func prepare(timeout:TimeInterval=30,stop:()->Void,isEngineRunning:()->Bool,runningPeers:(()->[NSRunningApplication])?=nil) async throws {
  guard updateLease != nil else { throw MinerError.message("The update session ended. Check for updates again.") }
  if !engineLeases.isEmpty { return }
  isPreparing=true
  stop()
  let deadline=ContinuousClock.now.advanced(by:.seconds(timeout))
  var asked=Set<pid_t>()
  do {
   while true {
    try Task.checkCancellation()
    let peers=runningPeers?() ?? matchingPeers()
    for peer in peers where asked.insert(peer.processIdentifier).inserted { _=peer.terminate() }
    if peers.isEmpty && !isEngineRunning() {
     // Retain all five locks together until Sparkle takes over. A newly opened
     // profile cannot launch a worker in the gap before application exit.
     do {
      var locks=[FileLease]()
      for profile in ["default"]+Settings.coins {
       locks.append(try FileLease(url:base.appendingPathComponent("Coordination/engine-\(profile).lock")))
      }
      engineLeases=locks
      return
     } catch { /* A supervised worker is still finishing its graceful stop. */ }
    }
    guard ContinuousClock.now<deadline else {
     throw MinerError.message("Idle Miner could not finish stopping every mining window and worker. The update was cancelled and your current app is unchanged. Close other Idle Miner windows, wait for mining to stop, then try again.")
    }
    try await Task.sleep(for:.milliseconds(100))
   }
  } catch { engineLeases.removeAll();isPreparing=false;throw error }
 }
}
