import AppKit
import Sparkle

@MainActor final class BuiltInUpdater:NSObject,SPUUpdaterDelegate {
 private weak var app:MinerApp?
 private let coordination:UpdateInstallationCoordinator
 private let driver:UpdateUserDriver
 private var updater:SPUUpdater?
 private var cycleActive=false
 var isPreparingToInstall:Bool { coordination.isPreparing }
 init(app:MinerApp) {
  self.app=app;coordination=UpdateInstallationCoordinator(base:app.baseFolder)
  let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Unknown"
  let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "Unknown"
  driver=UpdateUserDriver(installedVersion:"\(version) (\(build))")
  super.init()
  driver.prepareForInstallation={ [weak self] in
   guard let self,let app=self.app else { throw MinerError.message("The update session ended. Check for updates again.") }
   try await self.coordination.prepare(stop:{app.stopMining()},isEngineRunning:{app.engine?.running ?? false})
  }
 }
 func checkForUpdates() {
  if cycleActive { driver.showUpdateInFocus();return }
  do {
   try coordination.beginCycle();cycleActive=true
   if updater==nil {
    let controller=SPUUpdater(hostBundle:Bundle.main,applicationBundle:Bundle.main,userDriver:driver,delegate:self)
    // Apply explicit-only policy even if an older defaults domain opted into
    // automatic checks. Merely constructing this wrapper never starts Sparkle.
    controller.automaticallyChecksForUpdates=false;controller.automaticallyDownloadsUpdates=false;controller.sendsSystemProfile=false
    _=controller.clearFeedURLFromUserDefaults()
    try controller.start();updater=controller
   }
   updater?.checkForUpdates()
  } catch {
   cycleActive=false;coordination.endCycle()
   let alert=NSAlert();alert.messageText="Could not check for updates";alert.informativeText=error.localizedDescription;alert.addButton(withTitle:"Close");alert.runModal()
  }
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
 func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?) {
  cycleActive=false;coordination.endCycle()
 }
}
