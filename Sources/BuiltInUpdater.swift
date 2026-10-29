import AppKit
import Sparkle

@MainActor final class BuiltInUpdater:NSObject,SPUUpdaterDelegate {
 private weak var app:MinerApp?
 private let coordination:UpdateInstallationCoordinator
 private let driver:UpdateUserDriver
 private var updater:SPUUpdater?
 private var broker:NSRunningApplication?
 private var cycleActive=false
 var isPreparingToInstall:Bool { coordination.isPreparing }
 init(app:MinerApp) {
  self.app=app;coordination=UpdateInstallationCoordinator(base:app.baseFolder)
  let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Unknown"
  let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "Unknown"
  driver=UpdateUserDriver(installedVersion:"\(version) (\(build))")
  super.init()
  driver.installationFailed={ [weak self] in self?.coordination.endCycle(discardResume:true);_=self?.broker?.terminate() }
  driver.prepareForInstallation={ [weak self] in
   guard let self,let app=self.app else { throw MinerError.message("The update session ended. Check for updates again.") }
   guard let item=self.driver.selectedUpdate else { throw MinerError.message("The update release information is unavailable.") }
   try self.coordination.captureResume(profile:app.profileName,coin:app.settings.coin,enabled:app.automaticMiningIntent,targetBuild:item.versionString,targetVersion:item.displayVersionString)
   try await self.coordination.prepare(stop:{app.stopMining()},isEngineRunning:{app.engine?.running ?? false})
   try self.coordination.finalizeResume()
  }
 }
 func checkForUpdates() {
  if cycleActive { driver.showUpdateInFocus();return }
  do { try coordination.beginCycle();cycleActive=true }
  catch { showCheckError(error);return }
  Task { [weak self] in
   guard let self else { return }
   do {
    let brokerURL=UpdateResumeBroker.bundleURL(in:Bundle.main.bundleURL)
    guard let bundle=Bundle(url:brokerURL) else { throw MinerError.message("The update relaunch helper is missing. Reinstall Idle Miner from its signed download before updating.") }
    let config=NSWorkspace.OpenConfiguration();config.createsNewApplicationInstance=true;config.activates=false
    config.arguments=["--wait-for-controller=\(getpid())"]
    self.broker=try await NSWorkspace.shared.openApplication(at:brokerURL,configuration:config)
    guard self.broker?.isTerminated==false else { throw MinerError.message("The update relaunch helper could not start.") }
    if self.updater==nil {
     let controller=SPUUpdater(hostBundle:Bundle.main,applicationBundle:bundle,userDriver:self.driver,delegate:self)
     // Apply explicit-only policy even if older defaults opted into checks.
     controller.automaticallyChecksForUpdates=false;controller.automaticallyDownloadsUpdates=false;controller.sendsSystemProfile=false
     _=controller.clearFeedURLFromUserDefaults()
     try controller.start();self.updater=controller
    }
    self.updater?.checkForUpdates()
   } catch { self.showCheckError(error) }
  }
 }
 private func showCheckError(_ error:Error) {
  cycleActive=false;coordination.endCycle(discardResume:true);_=broker?.terminate()
  let alert=NSAlert();alert.messageText="Could not check for updates";alert.informativeText=error.localizedDescription;alert.addButton(withTitle:"Close");alert.runModal()
 }
 func updaterShouldPromptForPermissionToCheck(forUpdates updater:SPUUpdater)->Bool { false }
 func feedURLString(for updater:SPUUpdater)->String? { "https://idleminer.app/updates/appcast.xml" }
 func feedParameters(for updater:SPUUpdater,sendingSystemProfile:Bool)->[[String:String]] { [] }
 func allowedSystemProfileKeys(for updater:SPUUpdater)->[String]? { [] }
 func updater(_ updater:SPUUpdater,mayPerform updateCheck:SPUUpdateCheck)throws {
  guard cycleActive,updateCheck == .updates else { throw MinerError.message("Updates are checked only when you choose Check for Updates.") }
 }
 func updater(_ updater:SPUUpdater,shouldDownloadReleaseNotesForUpdate item:SUAppcastItem)->Bool {
  // Release notes travel in the appcast. Avoid a separate HTML request and any
  // external resources that could be referenced by a release notes page.
  false
 }
 func updaterWillRelaunchApplication(_ updater:SPUUpdater) {
  // This callback is Sparkle's successful installation handoff, not ordinary
  // application termination, download completion, or an install-on-quit request.
  do { try coordination.armResume() }
  catch { coordination.endCycle(discardResume:true) }
 }
 func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?) {
  let armed=coordination.hasArmedResume
  cycleActive=false;coordination.endCycle(discardResume:error != nil)
  if error != nil || !armed { _=broker?.terminate() }
 }
}
