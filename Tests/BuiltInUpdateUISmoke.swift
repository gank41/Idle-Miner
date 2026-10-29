import AppKit
import Sparkle

// SPUUserUpdateState exposes NSSecureCoding as its public construction API.
// This keyed fixture represents a user-initiated, not-yet-downloaded update.
private final class UpdateStateFixtureCoder:NSCoder {
 override var allowsKeyedCoding:Bool { true }
 override func containsValue(forKey key:String)->Bool { true }
 override func decodeInteger(forKey key:String)->Int { 0 }
 override func decodeBool(forKey key:String)->Bool { true }
}

@main struct BuiltInUpdateUISmoke {
 @MainActor static func main() {
  // Keep AppKit's event loop alive while async driver replies are outstanding.
  // A bare async command-line main can exit as soon as its dispatch queue drains.
  Task { @MainActor in
   do { try await runTests();exit(0) }
   catch { FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8));exit(1) }
  }
  NSApplication.shared.run()
 }
 @MainActor private static func runTests() async throws {
  let application=NSApplication.shared
  application.setActivationPolicy(.accessory)
  let repo=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent()
  application.applicationIconImage=NSImage(contentsOf:repo.appendingPathComponent("macOS/Resources/IdleMiner.icns"))
  let updateState=SPUUserUpdateState(coder:UpdateStateFixtureCoder())!
  precondition(updateState.stage == .notDownloaded,"Public coding fixture must represent an undownloaded update")
  let releaseNotes="""
  Idle Miner 1.9

  • Check for updates automatically, daily or weekly.
  • Receive a notification when an update is available.
  • Choose when to download and install the update.

  Your currencies and Automatic mining preference are restored after updating.
  """
  func fixture(version:String="12",extra:[String:Any]=[:])->SUAppcastItem {
   var dictionary:[String:Any]=["title":"Idle Miner 1.9","description":releaseNotes,"sparkle:descriptionFormat":"plain-text","enclosure":["url":"https://idleminer.app/downloads/v1.9/Idle-Miner-1.9-macOS.dmg","sparkle:version":version,"sparkle:shortVersionString":"1.9"]]
   dictionary.merge(extra,uniquingKeysWith:{$1})
   // Public deprecated initializer is sufficient for UI and OS-bound fixtures;
   // no runtime-dependent Sparkle isOK property is used by these tests.
   return SUAppcastItem(dictionary:dictionary)!
  }
  let item=fixture()
  let currentItem=fixture(version:"11",extra:["description":releaseNotes.replacingOccurrences(of:"Idle Miner 1.9",with:"Idle Miner 1.8"),"enclosure":["url":"https://idleminer.app/downloads/v1.8/Idle-Miner-1.8-macOS.dmg","sparkle:version":"11","sparkle:shortVersionString":"1.8"]])
  let noUpdate=NSError(domain:SUSparkleErrorDomain,code:1001,userInfo:[NSLocalizedDescriptionKey:"Idle Miner is up to date.",SPULatestAppcastItemFoundKey:currentItem,SPUNoUpdateFoundReasonKey:SPUNoUpdateFoundReason.onLatestVersion.rawValue])
  let detailedError=NSError(domain:"Fixture",code:1,userInfo:[NSLocalizedDescriptionKey:String(repeating:"The update service could not be reached. ",count:15)])
  let background=UpdateUserDriver(installedVersion:"1.8 (11)")
  var notifications=0,preparations=0,failures=0
  background.backgroundUpdateFound={ _ in notifications+=1 }
  background.prepareForInstallation={ preparations+=1 }
  background.installationFailed={ failures+=1 }
  background.isBackgroundCheck=true
  let activeBefore=application.isActive
  let backgroundAvailable=Task { await background.showUpdateFound(with:item,state:updateState) }
  await Task.yield()
  precondition(background.updateWindow==nil,"Background update must never open a window")
  let backgroundChoice=await backgroundAvailable.value
  precondition(backgroundChoice == .dismiss,"Background available update must dismiss without downloading")
  precondition(notifications==1 && preparations==0 && background.updateWindow==nil,"Background available update must only report a notification candidate")
  let incompatible=fixture(extra:["sparkle:minimumSystemVersion":"999.0"])
  let incompatibleChoice=await background.showUpdateFound(with:incompatible,state:updateState)
  precondition(incompatibleChoice == .dismiss,"Incompatible background update must dismiss")
  let obsolete=fixture(extra:["sparkle:maximumSystemVersion":"0.1"])
  let obsoleteChoice=await background.showUpdateFound(with:obsolete,state:updateState)
  precondition(obsoleteChoice == .dismiss,"A background release for an older OS must dismiss")
  let informational=SUAppcastItem(dictionary:["title":"Information only","link":"https://idleminer.app","sparkle:version":"12"])!
  precondition(informational.isInformationOnlyUpdate,"Fixture must exercise the information-only branch")
  let informationalChoice=await background.showUpdateFound(with:informational,state:updateState)
  precondition(informationalChoice == .dismiss,"Information-only background update must dismiss")
  let silentNotFound=Task { await background.showUpdateNotFoundWithError(noUpdate) };await Task.yield()
  precondition(background.updateWindow==nil,"Background current version must never open a window");await silentNotFound.value
  let silentError=Task { await background.showUpdaterError(detailedError) };await Task.yield()
  precondition(background.updateWindow==nil,"Background errors must never open a window");await silentError.value
  let silentFinished=Task { await background.showUpdateInstalledAndRelaunched(false) };await Task.yield()
  precondition(background.updateWindow==nil,"Background completion must never open a window");await silentFinished.value
  let backgroundInstall=await background.showReadyToInstallAndRelaunch()
  var backgroundDownloadCancelled=false
  background.showDownloadInitiated { backgroundDownloadCancelled=true }
  background.showUpdateInFocus()
  background.dismissUpdateInstallation()
  precondition(backgroundDownloadCancelled,"An unsolicited background download must be cancelled")
  precondition(backgroundInstall == .skip && notifications==1 && preparations==0 && failures==0,"Background callbacks must never prepare installation or invoke foreground failure handling")
  precondition(background.updateWindow==nil && application.isActive==activeBefore,"Background no-update, failure and completion must stay invisible and never activate the app")

  let driver=UpdateUserDriver(installedVersion:"1.8 (11)")
  driver.isBackgroundCheck=true
  driver.configureAutomaticChecks(enabled:true,frequency:"weekly")
  var cancelled=false
  driver.showUserInitiatedUpdateCheck { cancelled=true }
  precondition(!driver.isBackgroundCheck,"A manual check must reset background presentation")
  guard let window=driver.updateWindow else { fatalError("Missing native update window") }
  window.contentView?.layoutSubtreeIfNeeded()
  precondition(window.isVisible,"Check progress must be visible")
  precondition(window.styleMask.contains(.resizable),"Release notes window must resize")
  func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap(descendants) }
  let views=descendants(window.contentView!)
  let buttons=views.compactMap{$0 as? NSButton}
  precondition(views.compactMap{$0 as? NSImageView}.contains{$0.accessibilityIdentifier()=="update-app-icon" && $0.image != nil},"Traditional updater must display the Idle Miner app icon")
  let primary=buttons.filter{!["update-release-notes-toggle","update-automatic-checks","update-check-frequency"].contains($0.accessibilityIdentifier())}
  precondition(Set(primary.map(\.title))==Set(["Close","Download and Install Now"]),"Offer only the requested two primary actions")
  let install=buttons.first{$0.title=="Download and Install Now"}!
  let close=buttons.first{$0.title=="Close"}!
  precondition(install.isHidden,"Never install before a release is found")
  let checkbox=buttons.first{$0.accessibilityIdentifier()=="update-automatic-checks"}!
  let frequency=views.compactMap{$0 as? NSPopUpButton}.first!
  precondition(checkbox.state == .on && frequency.titleOfSelectedItem=="Weekly","Footer must reflect Settings preferences")
  var preferenceChanges=[(Bool?,String?)]()
  driver.automaticCheckPreferencesChanged={ enabled,value in preferenceChanges.append((enabled,value)) }
  driver.prepareForInstallation={ preparations+=1 }
  checkbox.performClick(nil)
  precondition(!frequency.isEnabled && preferenceChanges.count==1 && preferenceChanges[0].0==false && preferenceChanges[0].1==nil && preparations==0,"Checkbox changes must send only consent, preserving freshly loaded frequency")
  checkbox.performClick(nil)
  precondition(preferenceChanges.count==2 && preferenceChanges[1].0==true && preferenceChanges[1].1==nil,"Enabling automatic checks must send only explicit consent")
  frequency.selectItem(at:0);application.sendAction(frequency.action!,to:frequency.target,from:frequency)
  precondition(frequency.isEnabled && preferenceChanges.count==3 && preferenceChanges[2].0==nil && preferenceChanges[2].1=="daily" && preparations==0,"Frequency-only changes must never replay stale consent or install")
  precondition(views.compactMap{$0 as? NSTextView}.first?.isRichText==false,"Release notes must be inert plain text")
  close.performClick(nil)
  precondition(cancelled && !window.isVisible,"Close must cancel an active check")
  let acknowledgement=Task { await driver.showUpdateNotFoundWithError(noUpdate) }
  await Task.yield()
  let notes=views.compactMap{$0 as? NSTextView}.first!
  precondition(notes.isHiddenOrHasHiddenAncestor,"Current-version notes must start collapsed")
  let disclosure=buttons.first{$0.accessibilityIdentifier()=="update-release-notes-toggle"}!
  precondition(!disclosure.isHiddenOrHasHiddenAncestor,"Current notes remain available on demand")
  let compactHeight=window.frame.height
  precondition(compactHeight<360,"Up-to-date window should open compact")
  disclosure.performClick(nil)
  precondition(!notes.isHiddenOrHasHiddenAncestor && notes.string.contains("Idle Miner 1.8"),"Disclosure must show the plain release notes")
  precondition(window.frame.height>compactHeight,"Expanding notes must make room for them")
  disclosure.performClick(nil)
  precondition(notes.isHiddenOrHasHiddenAncestor && window.frame.height==compactHeight,"Notes must collapse again")
  close.performClick(nil);await acknowledgement.value

  func assertNoClipping() {
   let content=window.contentView!;content.layoutSubtreeIfNeeded()
   for view in [checkbox,frequency,close,install] where !view.isHiddenOrHasHiddenAncestor {
    let bounds=view.convert(view.bounds,to:content)
    precondition(content.bounds.insetBy(dx:-1,dy:-1).contains(bounds),"Native updater control clipped: \(view)")
   }
   precondition(checkbox.frame.maxX+8<frequency.frame.minX,"Preference controls must not overlap at minimum width")
   precondition(install.isHidden || close.frame.maxX<=install.frame.minX,"Primary actions must not overlap")
  }
  func snapshot(_ name:String,_ appearance:NSAppearance.Name) async throws {
   window.appearance=NSAppearance(named:appearance)
   try await Task.sleep(for:.milliseconds(100))
   let content=window.contentView!;content.layoutSubtreeIfNeeded();content.displayIfNeeded()
   guard let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) else { fatalError("Cannot snapshot updater view") }
   window.effectiveAppearance.performAsCurrentDrawingAppearance { content.cacheDisplay(in:content.bounds,to:bitmap) }
   let data=bitmap.representation(using:.png,properties:[:])!
   try data.write(to:URL(fileURLWithPath:"/private/tmp/idle-updater-\(name).png"))
  }
  let available=Task { await driver.showUpdateFound(with:item,state:updateState) }
  await Task.yield();window.contentView?.layoutSubtreeIfNeeded()
  precondition(!notes.isHiddenOrHasHiddenAncestor && !install.isHidden,"Available updates must display release notes and an explicit install action by default")
  var frame=window.frameRect(forContentRect:NSRect(x:0,y:0,width:window.contentMinSize.width,height:window.contentMinSize.height))
  frame.origin=window.frame.origin;window.setFrame(frame,display:true)
  assertNoClipping()
  try await snapshot("available-light",.aqua);try await snapshot("available-dark",.darkAqua)
  close.performClick(nil)
  let availableChoice=await available.value
  precondition(availableChoice == .dismiss && preparations==0,"Closing an available update must never prepare or install it")

  driver.showUserInitiatedUpdateCheck { cancelled=true }
  precondition(disclosure.isHiddenOrHasHiddenAncestor && notes.isHiddenOrHasHiddenAncestor,"A repeat check must clear stale notes and disclosure state")
  close.performClick(nil)
  let failureAcknowledgement=Task { await driver.showUpdaterError(detailedError) }
  await Task.yield();window.contentView?.layoutSubtreeIfNeeded()
  let status=views.compactMap{$0 as? NSTextField}.first{$0.accessibilityIdentifier()=="update-status"}!
  let requiredHeight=status.cell!.cellSize(forBounds:NSRect(x:0,y:0,width:status.bounds.width,height:CGFloat.greatestFiniteMagnitude)).height
  precondition(status.bounds.height>=requiredHeight-1,"A compact window must still show the full error")
  assertNoClipping();try await snapshot("error-dark",.darkAqua)
  close.performClick(nil);await failureAcknowledgement.value
  let current=Task { await driver.showUpdateNotFoundWithError(noUpdate) };await Task.yield()
  precondition(window.frame.height<360,"Current-version dialog must remain compact at minimum width")
  assertNoClipping();try await snapshot("current-light",.aqua)
  close.performClick(nil);await current.value

  driver.showDownloadInitiated { cancelled=true }
  driver.showDownloadDidReceiveExpectedContentLength(100)
  driver.showDownloadDidReceiveData(ofLength:35)
  precondition(views.compactMap{$0 as? NSProgressIndicator}.first?.doubleValue==0.35,"Download progress must reflect bytes")
  driver.showDownloadDidStartExtractingUpdate()
  precondition(!close.isEnabled,"Do not abandon the installer after extraction begins")
  let decision=await driver.showReadyToInstallAndRelaunch()
  precondition(decision == .skip,"A cached or unsolicited update must never install without explicit consent")
  driver.dismissUpdateInstallation()
  print("PASS: traditional native updater, light/dark snapshots at minimum width, compact current status (\(Int(compactHeight))px), optional notes, readable errors, preference callbacks, background silence and explicit consent")
 }
}
