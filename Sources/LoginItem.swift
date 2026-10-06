import AppKit
import ServiceManagement

@MainActor protocol LoginItemManaging {
 var status:SMAppService.Status { get }
 func setEnabled(_ enabled:Bool)throws
 func openSystemSettings()
}
@MainActor final class SystemLoginItem:LoginItemManaging {
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
  loginItem.title=pending ? "Start at Login (Approval Needed)" : "Start at Login"
  loginApprovalItem.isHidden = !pending; loginApprovalButton.isHidden = !pending
  if pending {
   loginHint.stringValue="Waiting for macOS approval. Open Login Items to allow Idle Miner, or click Start at Login again to cancel."
  } else {
   loginHint.stringValue="Applies immediately. Opens Idle Miner when you sign in; choose Start Mining to begin mining."
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
  refreshLoginItem()
 }
 @objc func openLoginSettings() { loginManager.openSystemSettings() }
 func menuWillOpen(_ menu:NSMenu) { refreshLoginItem() }
 func applicationDidBecomeActive(_ notification:Notification) { refreshLoginItem() }
}
