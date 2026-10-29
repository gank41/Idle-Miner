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
  precondition(Set(buttons.filter{$0.accessibilityIdentifier() != "update-release-notes-toggle"}.map(\.title))==Set(["Close","Download and Install Now"]),"Offer only the requested two actions")
  precondition(buttons.first{$0.title=="Download and Install Now"}?.isHidden==true,"Never install before a release is found")
  precondition(views.compactMap{$0 as? NSTextView}.first?.isRichText==false,"Release notes must be inert plain text")
  buttons.first{$0.title=="Close"}!.performClick(nil)
  precondition(cancelled && !window.isVisible,"Close must cancel an active check")
  let item=SUAppcastItem(dictionary:["title":"Idle Miner 1.8", "description":"Long optional release notes.\n"+String(repeating:"Optional history. ",count:80), "sparkle:descriptionFormat":"plain-text", "enclosure":["url":"https://idleminer.app/downloads/v1.8/Idle-Miner-1.8-macOS.dmg","sparkle:version":"11","sparkle:shortVersionString":"1.8"]])
  let noUpdate=NSError(domain:SUSparkleErrorDomain,code:1001,userInfo:[NSLocalizedDescriptionKey:"Idle Miner is up to date.",SPULatestAppcastItemFoundKey:item!,SPUNoUpdateFoundReasonKey:SPUNoUpdateFoundReason.onLatestVersion.rawValue])
  let acknowledgement=Task { await driver.showUpdateNotFoundWithError(noUpdate) }
  await Task.yield()
  let notes=descendants(window.contentView!).compactMap{$0 as? NSTextView}.first!
  precondition(notes.isHiddenOrHasHiddenAncestor,"Current-version notes must start collapsed")
  guard let disclosure=descendants(window.contentView!).compactMap({$0 as? NSButton}).first(where:{$0.accessibilityIdentifier()=="update-release-notes-toggle"}) else { fatalError("Optional Release Notes disclosure is missing") }
  precondition(!disclosure.isHiddenOrHasHiddenAncestor,"Current notes remain available on demand")
  let compactHeight=window.frame.height
  precondition(compactHeight<360,"Up-to-date window should open compact")
  disclosure.performClick(nil)
  precondition(!notes.isHiddenOrHasHiddenAncestor && notes.string.contains("Optional history"),"Disclosure must show the plain release notes")
  precondition(window.frame.height>compactHeight,"Expanding notes must make room for them")
  disclosure.performClick(nil)
  precondition(notes.isHiddenOrHasHiddenAncestor && window.frame.height==compactHeight,"Notes must collapse again")
  buttons.first{$0.title=="Close"}!.performClick(nil);await acknowledgement.value
  driver.showUserInitiatedUpdateCheck { cancelled=true }
  precondition(disclosure.isHiddenOrHasHiddenAncestor && notes.isHiddenOrHasHiddenAncestor,"A repeat check must clear stale notes and disclosure state")
  buttons.first{$0.title=="Close"}!.performClick(nil)
  let detailedError=NSError(domain:"Fixture",code:1,userInfo:[NSLocalizedDescriptionKey:String(repeating:"The update service could not be reached. ",count:15)])
  let failureAcknowledgement=Task { await driver.showUpdaterError(detailedError) }
  await Task.yield();window.contentView?.layoutSubtreeIfNeeded()
  let status=descendants(window.contentView!).compactMap{$0 as? NSTextField}.first{$0.accessibilityIdentifier()=="update-status"}!
  let requiredHeight=status.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:status.bounds.width,height:CGFloat.greatestFiniteMagnitude)).height
  precondition(status.bounds.height>=requiredHeight-1,"A compact window must still show the full error")
  buttons.first{$0.title=="Close"}!.performClick(nil);await failureAcknowledgement.value
  driver.showDownloadInitiated { cancelled=true }
  driver.showDownloadDidReceiveExpectedContentLength(100)
  driver.showDownloadDidReceiveData(ofLength:35)
  precondition(views.compactMap{$0 as? NSProgressIndicator}.first?.doubleValue==0.35,"Download progress must reflect bytes")
  driver.showDownloadDidStartExtractingUpdate()
  precondition(!buttons.first{$0.title=="Close"}!.isEnabled,"Do not abandon the installer after extraction begins")
  let decision=await driver.showReadyToInstallAndRelaunch()
  precondition(decision == .skip,"A cached or unsolicited update must never install without explicit consent")
  driver.dismissUpdateInstallation()
  print("PASS: native Sparkle custom driver window, compact current status, optional release notes, readable errors, cancellation, progress and explicit consent")
 }
}
