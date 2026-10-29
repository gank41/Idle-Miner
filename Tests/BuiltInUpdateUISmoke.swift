import AppKit
import Sparkle

@main struct BuiltInUpdateUISmoke {
 @MainActor static func main() async throws {
  let application=NSApplication.shared
  application.setActivationPolicy(.accessory)
  let driver=UpdateUserDriver(installedVersion:"1.8 (11)")
  var cancelled=false
  driver.showUserInitiatedUpdateCheck { cancelled=true }
  guard let window=driver.updateWindow else { fatalError("Missing native update window") }
  window.contentView?.layoutSubtreeIfNeeded()
  precondition(window.isVisible,"Check progress must be visible")
  precondition(window.styleMask.contains(.resizable),"Release notes window must resize")
  func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(descendants) }
  let views=descendants(window.contentView!)
  let buttons=views.compactMap{$0 as? NSButton}
  precondition(Set(buttons.map(\.title))==Set(["Close","Download and Install Now"]),"Offer only the requested two actions")
  precondition(buttons.first{$0.title=="Download and Install Now"}?.isHidden==true,"Never install before a release is found")
  precondition(views.compactMap{$0 as? NSTextView}.first?.isRichText==false,"Release notes must be inert plain text")
  buttons.first{$0.title=="Close"}!.performClick(nil)
  precondition(cancelled && !window.isVisible,"Close must cancel an active check")
  driver.showDownloadInitiated { cancelled=true }
  driver.showDownloadDidReceiveExpectedContentLength(100)
  driver.showDownloadDidReceiveData(ofLength:35)
  precondition(views.compactMap{$0 as? NSProgressIndicator}.first?.doubleValue==0.35,"Download progress must reflect bytes")
  driver.showDownloadDidStartExtractingUpdate()
  precondition(!buttons.first{$0.title=="Close"}!.isEnabled,"Do not abandon the installer after extraction begins")
  let decision=await driver.showReadyToInstallAndRelaunch()
  precondition(decision == .skip,"A cached or unsolicited update must never install without explicit consent")
  driver.dismissUpdateInstallation()
  print("PASS: native Sparkle custom driver window, cancellation, progress and explicit consent")
 }
}
