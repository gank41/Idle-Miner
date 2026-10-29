import AppKit

@main struct BuiltInUpdatePolicyTests {
 @MainActor static func main() async throws {
  func expect(_ value:Bool,_ message:String) { if !value { fatalError(message) } }
  var state=UpdatePresentationState(installedVersion:"1.8 (11)")
  expect(state.installButtonTitle==nil,"Checking must not offer installation")
  state.latestVersion="1.9 (12)";state.phase = .available
  expect(state.installButtonTitle=="Download and Install Now","Installation wording states the immediate action")
  expect(state.installedVersion=="1.8 (11)" && state.latestVersion=="1.9 (12)","Both versions remain visible")
  state.phase = .downloading
  expect(state.installButtonTitle==nil && state.canClose,"Download may be cancelled without a second install choice")
  state.phase = .extracting
  expect(!state.canClose,"Extraction cannot be abandoned into an install-on-quit session")
  state.phase = .preparing
  expect(!state.canClose,"Do not abandon the installation handoff midway")
  let notes=UpdateReleaseNotes.plainText("<h1>Changes</h1><script>alert('bad')</script><p>Fast &amp; safe</p><img src='https://private.example/tracker'>")
  expect(notes.contains("Fast & safe") && !notes.contains("alert") && !notes.contains("tracker"),"Notes are inert readable text")
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("update-policy-\(UUID())",isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer { try? FileManager.default.removeItem(at:root) }
  let real=root.appendingPathComponent("Idle Miner.app");try FileManager.default.createDirectory(at:real,withIntermediateDirectories:true)
  let link=root.appendingPathComponent("alias.app");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:real)
  expect(UpdateInstallationCoordinator.matches(bundleURL:link,bundleIdentifier:"app.test",hostURL:real,hostIdentifier:"app.test"),"Resolve exact bundle aliases")
  expect(!UpdateInstallationCoordinator.matches(bundleURL:root.appendingPathComponent("Other.app"),bundleIdentifier:"app.test",hostURL:real,hostIdentifier:"app.test"),"Do not terminate a different installation")
  expect(!UpdateInstallationCoordinator.matches(bundleURL:real,bundleIdentifier:"other",hostURL:real,hostIdentifier:"app.test"),"Require the exact bundle identifier")
  let controller=UpdateInstallationCoordinator(base:root)
  try controller.beginCycle()
  let competing=UpdateInstallationCoordinator(base:root)
  do { try competing.beginCycle();fatalError("Concurrent update cycle admitted") } catch {}
  let held=try FileLease(url:root.appendingPathComponent("Coordination/engine-BTC.lock"))
  do { try await controller.prepare(timeout:0.03,stop:{},isEngineRunning:{false},runningPeers:{[]});fatalError("Installation admitted a locked worker") } catch {}
  withExtendedLifetime(held){}
  controller.endCycle()
  try competing.beginCycle();competing.endCycle()
  let readyRoot=root.appendingPathComponent("ready")
  let ready=UpdateInstallationCoordinator(base:readyRoot);try ready.beginCycle()
  var stopped=false
  try await ready.prepare(timeout:0.2,stop:{stopped=true},isEngineRunning:{false},runningPeers:{[]})
  expect(stopped,"Stop the local engine before acquiring all worker leases")
  for profile in ["default"]+Settings.coins {
   do { _=try FileLease(url:readyRoot.appendingPathComponent("Coordination/engine-\(profile).lock"));fatalError("Ready must retain every worker lease") } catch {}
  }
  ready.endCycle()
  _=try FileLease(url:readyRoot.appendingPathComponent("Coordination/engine-default.lock"))
  let releasedRoot=root.appendingPathComponent("released")
  let released=UpdateInstallationCoordinator(base:releasedRoot);try released.beginCycle()
  var blocking:FileLease?=try FileLease(url:releasedRoot.appendingPathComponent("Coordination/engine-ETH.lock"))
  let releaseTask=Task { @MainActor in
   try await Task.sleep(for:.milliseconds(30))
   withExtendedLifetime(blocking){}
   blocking=nil
  }
  try await released.prepare(timeout:1,stop:{},isEngineRunning:{false},runningPeers:{[]})
  try await releaseTask.value
  expect(blocking==nil,"Wait for an actual worker lock release before allowing installation")
  try await released.prepare(timeout:0.1,stop:{fatalError("Repeated handoff must not restart preparation")},isEngineRunning:{false},runningPeers:{[]})
  released.endCycle()
  let cancelledRoot=root.appendingPathComponent("cancelled")
  let cancelled=UpdateInstallationCoordinator(base:cancelledRoot);try cancelled.beginCycle()
  let cancelledTask=Task { @MainActor in try await cancelled.prepare(timeout:1,stop:{},isEngineRunning:{true},runningPeers:{[]}) }
  cancelledTask.cancel()
  do { try await cancelledTask.value;fatalError("Cancelled preparation must never install") } catch is CancellationError {}
  expect(!cancelled.isPreparing,"Cancellation restores the controller's stopped usable state")
  cancelled.endCycle()
  let readonly=root.appendingPathComponent("readonly")
  try FileManager.default.createDirectory(at:readonly,withIntermediateDirectories:true)
  try FileManager.default.setAttributes([.posixPermissions:0o500],ofItemAtPath:readonly.path)
  do { try UpdateInstallationCoordinator(base:readonly).beginCycle();fatalError("Non-writable coordination must fail closed") } catch {}
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:readonly.path)
  let bad=root.appendingPathComponent("file");try Data().write(to:bad)
  do { try UpdateInstallationCoordinator(base:bad).beginCycle();fatalError("Inaccessible coordination must fail closed") } catch {}
  print("PASS: built-in updater consent, inert notes, exact bundle matching, update and engine leases")
 }
}
