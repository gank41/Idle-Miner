import AppKit
import Sparkle
import UserNotifications

@MainActor private final class UpdateNotifications:NSObject,UNUserNotificationCenterDelegate {
 private let center:UNUserNotificationCenter?
 var openUpdate:(()->Void)?
 init(enabled:Bool) {
  center=enabled ? UNUserNotificationCenter.current():nil
  super.init();center?.delegate=self
 }
 func requestPermission(completion:@escaping @MainActor @Sendable ()->Void) {
  guard let center else { completion();return }
  center.requestAuthorization(options:[.alert,.sound]) { _,_ in DispatchQueue.main.async { completion() } }
 }
 func whenAuthorized(_ action:@escaping @MainActor @Sendable ()->Void) {
  center?.getNotificationSettings { settings in
   guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
   DispatchQueue.main.async { action() }
  }
 }
 func notify(_ update:AvailableUpdate,failed:@escaping @MainActor @Sendable ()->Void) {
  guard let center else { return }
  let content=UNMutableNotificationContent();content.title="Idle Miner \(update.version) is available"
  content.body="Open Idle Miner to review the changes and choose when to install.";content.sound = .default
  let request=UNNotificationRequest(identifier:"idle-miner-update-\(update.build)",content:content,trigger:nil)
  center.add(request) { error in if error != nil { DispatchQueue.main.async { failed() } } }
 }
 nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse) async {
  await openUpdateWindow()
 }
 private func openUpdateWindow() { openUpdate?() }
 nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification) async->UNNotificationPresentationOptions { [.banner,.sound] }
}

@MainActor final class BuiltInUpdater:NSObject,SPUUpdaterDelegate {
 private weak var app:MinerApp?
 private let coordination:UpdateInstallationCoordinator
 private let schedule:AutomaticUpdateStore
 private let notifications:UpdateNotifications
 private let driver:UpdateUserDriver
 private var updater:SPUUpdater?
 private var broker:NSRunningApplication?
 private var cycleActive=false
 private var automaticCycle=false
 private var pendingManualCheck=false
 private var nextAutomaticPoll:TimeInterval?
 private var available:AvailableUpdate?
 private let installedBuild:Int
 var isPreparingToInstall:Bool { coordination.isPreparing }
 var menuTitle:String { app?.settings.automaticUpdateChecks==true && available != nil ? "Update Available · \(available!.version)…":"Check for Updates…" }
 init(app:MinerApp) {
  self.app=app;coordination=UpdateInstallationCoordinator(base:app.baseFolder);schedule=AutomaticUpdateStore(base:app.baseFolder)
  notifications=UpdateNotifications(enabled:app.automaticUpdateNetworkingEnabled && Bundle.main.bundleIdentifier=="local.jeff.idleminer")
  let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Unknown"
  let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "Unknown"
  installedBuild=Int(build) ?? 0
  driver=UpdateUserDriver(installedVersion:"\(version) (\(build))")
  super.init()
  notifications.openUpdate={ [weak self] in self?.checkForUpdates() }
  driver.backgroundUpdateFound={ [weak self] item in self?.foundAutomaticUpdate(item) }
  driver.automaticCheckPreferencesChanged={ [weak app] enabled,frequency in app?.setAutomaticUpdatePreferences(enabled:enabled,frequency:frequency) }
  driver.installationFailed={ [weak self] in self?.coordination.endCycle(discardResume:true);_=self?.broker?.terminate() }
  driver.prepareForInstallation={ [weak self] in
   guard let self,let app=self.app else { throw MinerError.message("The update session ended. Check for updates again.") }
   guard let item=self.driver.selectedUpdate else { throw MinerError.message("The update release information is unavailable.") }
   try self.coordination.captureResume(profile:app.profileName,coin:app.settings.coin,enabled:app.automaticMiningIntent,targetBuild:item.versionString,targetVersion:item.displayVersionString)
   try await self.coordination.prepare(stop:{app.stopMining()},isEngineRunning:{app.engine?.running ?? false})
   try self.coordination.finalizeResume()
  }
 }
 func configurePreferences() {
  guard let app else { return }
  driver.configureAutomaticChecks(enabled:app.settings.automaticUpdateChecks,frequency:app.settings.updateCheckFrequency)
 }
 func preferencesChanged(requestNotifications:Bool) {
  configurePreferences();nextAutomaticPoll=nil
  if requestNotifications { notifications.requestPermission { [weak self] in self?.deliverAvailableNotification() } }
  pollAutomaticChecks()
 }
 func pollAutomaticChecks(now:TimeInterval=Date().timeIntervalSince1970) {
  guard let app,app.automaticUpdateNetworkingEnabled,!app.quitting,app.settings.automaticUpdateChecks,!cycleActive else { return }
  if let next=nextAutomaticPoll,now<next,next-now<=60 { return }
  nextAutomaticPoll=now+60
  available=try? schedule.availableUpdate(installedBuild:installedBuild)
  deliverAvailableNotification()
  do { try coordination.beginCycle() }
  catch { return } // A manual check in another currency always gets priority.
  do {
   guard try schedule.claimDue(enabled:app.settings.automaticUpdateChecks,frequency:app.settings.updateCheckFrequency,now:now) else { coordination.endCycle();return }
   beginCheck(automatically:true)
  } catch { coordination.endCycle(discardResume:true) }
 }
 func checkForUpdates() {
  guard let app,!app.quitting else { return }
  if cycleActive {
   if automaticCycle { pendingManualCheck=true } else { driver.showUpdateInFocus() }
   return
  }
  do { try coordination.beginCycle();beginCheck(automatically:false) }
  catch { showCheckError(error,automatically:false) }
 }
 private func beginCheck(automatically:Bool) {
  cycleActive=true;automaticCycle=automatically;driver.isBackgroundCheck=automatically;configurePreferences()
  Task { [weak self] in
   guard let self else { return }
   do {
    let brokerURL=UpdateResumeBroker.bundleURL(in:Bundle.main.bundleURL)
    guard let bundle=Bundle(url:brokerURL) else { throw MinerError.message("The update relaunch helper is missing. Reinstall Idle Miner from its signed download before updating.") }
    if !automatically {
     let config=NSWorkspace.OpenConfiguration();config.createsNewApplicationInstance=true;config.activates=false
     config.arguments=["--wait-for-controller=\(getpid())"]
     config.environment=["IDLE_MINER_STATE":self.app?.baseFolder.path ?? UpdateResumeBroker.defaultBase.path]
     self.broker=try await NSWorkspace.shared.openApplication(at:brokerURL,configuration:config)
     guard self.broker?.isTerminated==false else { throw MinerError.message("The update relaunch helper could not start.") }
    }
    if self.updater==nil {
     let controller=SPUUpdater(hostBundle:Bundle.main,applicationBundle:bundle,userDriver:self.driver,delegate:self)
     // The shared scheduler owns timing. Sparkle never schedules downloads or
     // installation itself; its probing API authenticates automatic checks.
     controller.automaticallyChecksForUpdates=false;controller.automaticallyDownloadsUpdates=false;controller.sendsSystemProfile=false
     _=controller.clearFeedURLFromUserDefaults()
     try controller.start();self.updater=controller
    }
    if automatically { self.updater?.checkForUpdateInformation() }
    else { self.updater?.checkForUpdates() }
   } catch { self.showCheckError(error,automatically:automatically) }
  }
 }
 private func showCheckError(_ error:Error,automatically:Bool) {
  cycleActive=false;automaticCycle=false;coordination.endCycle(discardResume:true);_=broker?.terminate()
  if !automatically {
   let alert=NSAlert();alert.messageText="Could not check for updates";alert.informativeText=error.localizedDescription;alert.addButton(withTitle:"Close");alert.runModal()
  }
  finishPendingManualCheck()
 }
 private func finishPendingManualCheck() {
  if pendingManualCheck {
   pendingManualCheck=false
   Task { [weak self] in await Task.yield();self?.checkForUpdates() }
  }
 }
 private func foundAutomaticUpdate(_ item:SUAppcastItem) {
  // Re-read consent after the request: another currency may have disabled it.
  guard let app,!app.quitting,let fresh=try? Settings.load(from:app.settingsURL),fresh.automaticUpdateChecks,
        !item.isInformationOnlyUpdate,item.signingValidationStatus == .succeeded,let build=Int(item.versionString),build>installedBuild else { return }
  let update=AvailableUpdate(version:item.displayVersionString,build:build)
  guard update.valid else { return }
  do {
   _=try schedule.recordAvailable(update,installedBuild:installedBuild,markNotified:false);available=update
   deliverAvailableNotification()
  } catch { /* Automatic checks never interrupt mining with an error window. */ }
 }
 private func deliverAvailableNotification() {
  guard let update=try? schedule.availableUpdate(installedBuild:installedBuild) else { return }
  notifications.whenAuthorized { [weak self] in
   guard let self,let app=self.app,!app.quitting,let fresh=try? Settings.load(from:app.settingsURL),fresh.automaticUpdateChecks else { return }
   do {
    // Dedup only once permission permits delivery; an unanswered prompt must
    // never consume this release's notification. Recheck consent after async I/O.
    if try self.schedule.recordAvailable(update,installedBuild:self.installedBuild) {
     self.notifications.notify(update) { [weak self] in try? self?.schedule.retryNotification(update) }
    }
   } catch { }
  }
 }
 func updaterShouldPromptForPermissionToCheck(forUpdates updater:SPUUpdater)->Bool { false }
 func feedURLString(for updater:SPUUpdater)->String? { "https://idleminer.app/updates/appcast.xml" }
 func feedParameters(for updater:SPUUpdater,sendingSystemProfile:Bool)->[[String:String]] { [] }
 func allowedSystemProfileKeys(for updater:SPUUpdater)->[String]? { [] }
 func updater(_ updater:SPUUpdater,mayPerform updateCheck:SPUUpdateCheck)throws {
  guard cycleActive else { throw MinerError.message("No update check was requested.") }
  if automaticCycle {
   guard updateCheck == .updateInformation,let app,let fresh=try? Settings.load(from:app.settingsURL),fresh.automaticUpdateChecks else { throw MinerError.message("Automatic checks are disabled.") }
  } else if updateCheck != .updates { throw MinerError.message("No automatic check was requested.") }
 }
 func updater(_ updater:SPUUpdater,didFindValidUpdate item:SUAppcastItem) {
  if automaticCycle { foundAutomaticUpdate(item) }
 }
 func updaterDidNotFindUpdate(_ updater:SPUUpdater,error:Error) {
  let reason=((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
  if reason==Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue) || reason==Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue) { try? schedule.clearAvailable();available=nil }
 }
 func updater(_ updater:SPUUpdater,shouldDownloadReleaseNotesForUpdate item:SUAppcastItem)->Bool { false }
 func updaterWillRelaunchApplication(_ updater:SPUUpdater) {
  do { try coordination.armResume() }
  catch { coordination.endCycle(discardResume:true) }
 }
 func updater(_ updater:SPUUpdater,didFinishUpdateCycleFor updateCheck:SPUUpdateCheck,error:Error?) {
  let armed=coordination.hasArmedResume
  cycleActive=false;automaticCycle=false;coordination.endCycle(discardResume:error != nil)
  if error != nil || !armed { _=broker?.terminate() }
  finishPendingManualCheck()
 }
}
