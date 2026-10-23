import AppKit
import ServiceManagement

@MainActor protocol LoginItemManaging {
 var status:SMAppService.Status { get }
 var launchedAtLogin:Bool { get }
 func setEnabled(_ enabled:Bool)throws
 func openSystemSettings()
}
extension LoginItemManaging { var launchedAtLogin:Bool { SystemLoginItem.wasLaunchedAtLogin } }
@MainActor final class SystemLoginItem:LoginItemManaging {
 static var wasLaunchedAtLogin:Bool {
  isLoginEvent(NSAppleEventManager.shared().currentAppleEvent)
 }
 static func isLoginEvent(_ event:NSAppleEventDescriptor?)->Bool {
  event?.eventID==kAEOpenApplication && event?.paramDescriptor(forKeyword:keyAEPropData)?.enumCodeValue==keyAELaunchedAsLogInItem
 }
 var status:SMAppService.Status { SMAppService.mainApp.status }
 func setEnabled(_ enabled:Bool)throws {
  if enabled { try SMAppService.mainApp.register() }
  else { try SMAppService.mainApp.unregister() }
 }
 func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

extension MinerApp {
 func refreshLoginItem() {
  guard loginItem != nil else { return }
  let status=loginManager.status
  let pending=status == .requiresApproval
  let state:NSControl.StateValue=status == .enabled ? .on : pending ? .mixed : .off
  loginItem.state=state; loginCheck.state=state
  loginMiningCheck.state=settings.startMiningAtLogin ? .on : .off
  loginMiningCheck.isEnabled=status == .enabled || pending
  loginItem.title=pending ? "Start at Login (Approval Needed)" : "Start at Login"
  loginApprovalItem.isHidden = !pending; loginApprovalButton.isHidden = !pending
  if pending {
   loginHint.stringValue="Waiting for macOS approval. Open Login Items to allow Idle Miner, or click Start at Login again to cancel."
  } else {
   loginHint.stringValue=settings.startMiningAtLogin ? "At login, automatically mines all currencies with valid saved wallets. Each needs its own dataset (about 2 GB); all share the CPU limit. Manual launches stay stopped." : "Applies immediately. Opens Idle Miner stopped when you sign in. The option above can start all configured currencies automatically."
  }
 }
 @objc func toggleLoginItem() {
  let status=loginManager.status
  let shouldEnable=status != .enabled && status != .requiresApproval
  do { try loginManager.setEnabled(shouldEnable) }
  catch {
   refreshLoginItem()
   alert("Could not change Start at Login. \(error.localizedDescription)\n\nMake sure Idle Miner is in Applications. You can also manage it in System Settings → General → Login Items.")
   return
  }
  if !shouldEnable { saveLoginMining(false) }
  refreshLoginItem()
 }
 @objc func openLoginSettings() { loginManager.openSystemSettings() }
 func menuWillOpen(_ menu:NSMenu) { refreshSharedSettings();refreshLoginItem() }
 func applicationDidBecomeActive(_ notification:Notification) { refreshLoginItem() }
}

extension MinerApp {
 func saveLoginMining(_ value:Bool) {
  do {
   var fresh=try Settings.load(from:settingsURL);fresh.switchCoin(to:settings.coin)
   try fresh.save(to:settingsURL,walletChanges:[:],updateDefaultCoin:false,startMiningAtLoginChange:value)
   lastSettingsData=nil;refreshSharedSettings()
  } catch { alert("Could not save automatic login mining. \(error.localizedDescription)") }
  refreshLoginItem()
 }
 @objc func toggleLoginMining() {
  guard loginManager.status == .enabled || loginManager.status == .requiresApproval else { refreshLoginItem();return }
  saveLoginMining(loginMiningCheck.state == .on)
 }
 func startConfiguredCurrenciesAtLogin(_ currencies:[String]) {
  guard profileName=="default",settings.startMiningAtLogin else { return }
  if currencies.contains(settings.coin) { startMining() }
  for coin in currencies where coin != settings.coin { openCurrencyInstance(coin,startMining:true,showStats:false) }
 }
}
