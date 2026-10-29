import AppKit
import Sparkle

@MainActor final class UpdateUserDriver:NSObject,SPUUserDriver,NSWindowDelegate {
 var prepareForInstallation:(() async throws->Void)?
 private(set) var state:UpdatePresentationState
 private(set) var updateWindow:NSWindow?
 private let versionLabel=NSTextField(wrappingLabelWithString:"")
 private let statusLabel=NSTextField(wrappingLabelWithString:"")
 private let notes=NSTextView()
 private let progress=NSProgressIndicator()
 private let installButton=NSButton(title:"Download and Install Now",target:nil,action:nil)
 private let closeButton=NSButton(title:"Close",target:nil,action:nil)
 private var choice:CheckedContinuation<SPUUserUpdateChoice,Never>?
 private var acknowledgement:CheckedContinuation<Void,Never>?
 private var cancellation:(()->Void)?
 private var closeChoice:SPUUserUpdateChoice = .dismiss
 private var expected:UInt64=0
 private var received:UInt64=0
 private var consented=false
 private var preserveFailureWindow=false
 init(installedVersion:String) { state=UpdatePresentationState(installedVersion:installedVersion);super.init() }
 private func ensureWindow() {
  guard updateWindow==nil else { return }
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:580,height:450),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
  window.title="Idle Miner Update";window.minSize=NSSize(width:460,height:340);window.isReleasedWhenClosed=false;window.delegate=self
  let content=window.contentView!
  let title=NSTextField(labelWithString:"Idle Miner Update");title.font = .boldSystemFont(ofSize:20)
  versionLabel.font = .systemFont(ofSize:13)
  statusLabel.setAccessibilityIdentifier("update-status")
  notes.isEditable=false;notes.isSelectable=true;notes.isRichText=false;notes.importsGraphics=false;notes.font = .systemFont(ofSize:13);notes.textContainerInset=NSSize(width:8,height:8)
  notes.frame=NSRect(x:0,y:0,width:520,height:180);notes.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
  notes.autoresizingMask=[.width];notes.isVerticallyResizable=true;notes.isHorizontallyResizable=false;notes.textContainer?.widthTracksTextView=true
  notes.setAccessibilityIdentifier("update-release-notes")
  let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;scroll.documentView=notes
  progress.style = .bar;progress.minValue=0;progress.maxValue=1
  installButton.target=self;installButton.action=#selector(installNow);installButton.bezelStyle = .rounded;installButton.setAccessibilityIdentifier("update-install-now")
  closeButton.target=self;closeButton.action=#selector(closeUpdate);closeButton.bezelStyle = .rounded;closeButton.keyEquivalent="\u{1b}"
  for view in [title,versionLabel,statusLabel,scroll,progress,installButton,closeButton] { view.translatesAutoresizingMaskIntoConstraints=false;content.addSubview(view) }
  NSLayoutConstraint.activate([
   title.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:22),title.topAnchor.constraint(equalTo:content.topAnchor,constant:20),
   versionLabel.leadingAnchor.constraint(equalTo:title.leadingAnchor),versionLabel.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-22),versionLabel.topAnchor.constraint(equalTo:title.bottomAnchor,constant:12),
   statusLabel.leadingAnchor.constraint(equalTo:title.leadingAnchor),statusLabel.trailingAnchor.constraint(equalTo:versionLabel.trailingAnchor),statusLabel.topAnchor.constraint(equalTo:versionLabel.bottomAnchor,constant:12),
   scroll.leadingAnchor.constraint(equalTo:title.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:versionLabel.trailingAnchor),scroll.topAnchor.constraint(equalTo:statusLabel.bottomAnchor,constant:12),scroll.bottomAnchor.constraint(equalTo:progress.topAnchor,constant:-16),
   progress.leadingAnchor.constraint(equalTo:title.leadingAnchor),progress.trailingAnchor.constraint(equalTo:versionLabel.trailingAnchor),progress.bottomAnchor.constraint(equalTo:closeButton.topAnchor,constant:-18),
   closeButton.trailingAnchor.constraint(equalTo:versionLabel.trailingAnchor),closeButton.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-18),
   installButton.trailingAnchor.constraint(equalTo:closeButton.leadingAnchor,constant:-10),installButton.centerYAnchor.constraint(equalTo:closeButton.centerYAnchor)
  ])
  window.center();updateWindow=window
 }
 private func render(_ status:String) {
  ensureWindow()
  versionLabel.stringValue="Installed: \(state.installedVersion)\nLatest: \(state.latestVersion ?? "Checking…")"
  statusLabel.stringValue=status
  installButton.isHidden=state.installButtonTitle==nil
  let canClose=state.canClose && (state.phase != .downloading || cancellation != nil)
  closeButton.isEnabled=canClose
  updateWindow?.standardWindowButton(.closeButton)?.isEnabled=canClose
  showUpdateInFocus()
 }
 func showUpdateInFocus() { updateWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
 private func record(_ item:SUAppcastItem) {
  state.latestVersion="\(item.displayVersionString) (\(item.versionString))"
  let embedded=item.itemDescription ?? ""
  notes.string=item.itemDescriptionFormat=="plain-text" ? String(embedded.prefix(262_144)):UpdateReleaseNotes.plainText(embedded)
  if notes.string.isEmpty { notes.string="Release notes are unavailable for this update." }
 }
 @objc private func installNow() {
  guard state.phase == .available,let reply=choice else { return }
  choice=nil;consented=true;state.phase = .downloading;render("Preparing the update download…")
  reply.resume(returning:.install)
 }
 @objc private func closeUpdate() {
  guard state.canClose,state.phase != .downloading || cancellation != nil else { return }
  let cancel=cancellation;cancellation=nil
  let reply=choice;choice=nil
  let ack=acknowledgement;acknowledgement=nil
  updateWindow?.orderOut(nil)
  cancel?();reply?.resume(returning:closeChoice);ack?.resume()
 }
 func windowShouldClose(_ sender:NSWindow)->Bool { closeUpdate();return false }
 func show(_ request:SPUUpdatePermissionRequest) async->SUUpdatePermissionResponse {
  SUUpdatePermissionResponse(automaticUpdateChecks:false,automaticUpdateDownloading:false,sendSystemProfile:false)
 }
 func showUserInitiatedUpdateCheck(cancellation:@escaping ()->Void) {
  preserveFailureWindow=false;consented=false;self.cancellation=cancellation
  state.phase = .checking;state.latestVersion=nil;notes.string="";progress.isIndeterminate=true;progress.startAnimation(nil)
  render("Checking for updates…")
 }
 func showUpdateFound(with item:SUAppcastItem,state updateState:SPUUserUpdateState) async->SPUUserUpdateChoice {
  cancellation=nil;record(item);progress.stopAnimation(nil);progress.isIndeterminate=false;progress.doubleValue=0
  if item.isInformationOnlyUpdate {
   state.phase = .finished;render("This release cannot be installed on this Mac.")
   await waitForAcknowledgement();return .dismiss
  }
  state.phase = .available;closeChoice=updateState.stage == .installing ? .skip:.dismiss
  render("Read the changes below. Installing will stop mining in all windows, update this copy of Idle Miner, and reopen it with mining stopped.")
  let result=await withCheckedContinuation { choice=$0 }
  if result == .install { return await prepareInstallation(installing:updateState.stage == .installing) }
  return result
 }
 func showUpdateReleaseNotes(with downloadData:SPUDownloadData) {
  guard let text=String(data:downloadData.data.prefix(262_144),encoding:.utf8) else { return }
  notes.string=UpdateReleaseNotes.plainText(text)
 }
 func showUpdateReleaseNotesFailedToDownloadWithError(_ error:Error) {
  if notes.string.isEmpty { notes.string="Release notes could not be loaded." }
 }
 func showUpdateNotFoundWithError(_ error:Error) async {
  cancellation=nil;progress.stopAnimation(nil);state.phase = .finished
  if let item=(error as NSError).userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem { record(item) }
  if state.latestVersion==nil { state.latestVersion="Unavailable" }
  render(error.localizedDescription)
  await waitForAcknowledgement()
 }
 func showUpdaterError(_ error:Error) async {
  cancellation=nil;progress.stopAnimation(nil);state.phase = .finished
  render("The update could not be completed. Your current app and preferences remain available.\n\n\(error.localizedDescription)")
  await waitForAcknowledgement()
 }
 private func waitForAcknowledgement() async { await withCheckedContinuation { acknowledgement=$0 } }
 func showDownloadInitiated(cancellation:@escaping ()->Void) {
  self.cancellation=cancellation;expected=0;received=0;state.phase = .downloading;progress.isIndeterminate=true;progress.startAnimation(nil)
  render("Downloading update… Close cancels the download.")
 }
 func showDownloadDidReceiveExpectedContentLength(_ length:UInt64) { expected=length;updateDownloadProgress() }
 func showDownloadDidReceiveData(ofLength length:UInt64) { received=received.addingReportingOverflow(length).overflow ? UInt64.max:received+length;updateDownloadProgress() }
 private func updateDownloadProgress() {
  guard expected>0 else { return }
  progress.stopAnimation(nil);progress.isIndeterminate=false;progress.doubleValue=min(1,Double(received)/Double(expected))
  statusLabel.stringValue="Downloading update… \(Int(progress.doubleValue*100))% · Close cancels the download."
 }
 func showDownloadDidStartExtractingUpdate() {
  cancellation=nil;state.phase = .extracting;progress.isIndeterminate=true;progress.startAnimation(nil)
  render("Verifying and preparing the downloaded update… macOS may ask for permission to replace this app.")
 }
 func showExtractionReceivedProgress(_ value:Double) { progress.stopAnimation(nil);progress.isIndeterminate=false;progress.doubleValue=max(0,min(1,value)) }
 func showReadyToInstallAndRelaunch() async->SPUUserUpdateChoice { await prepareInstallation() }
 private func prepareInstallation(installing:Bool=true) async->SPUUserUpdateChoice {
  guard consented,let prepareForInstallation else { return .skip }
  state.phase = .preparing;render("Stopping mining and closing other Idle Miner windows…")
  do {
   try await prepareForInstallation()
   state.phase = installing ? .installing:.downloading
   render(installing ? "Installing update… Idle Miner will reopen with mining stopped.":"Preparing the update download… Mining is stopped.")
   return .install
  }
  catch {
   state.phase = .finished;preserveFailureWindow=true;render(error.localizedDescription)
   return .skip
  }
 }
 func showInstallingUpdate(withApplicationTerminated terminated:Bool,retryTerminatingApplication:@escaping ()->Void) {
  state.phase = .installing;render("Installing update… Idle Miner will reopen with mining stopped.")
 }
 func showUpdateInstalledAndRelaunched(_ relaunched:Bool) async {
  state.phase = .finished;render(relaunched ? "Update installed. Idle Miner has reopened with mining stopped.":"Update installed.")
  await waitForAcknowledgement()
 }
 func dismissUpdateInstallation() {
  cancellation=nil
  let reply=choice;choice=nil;reply?.resume(returning:.skip)
  let ack=acknowledgement;acknowledgement=nil;ack?.resume()
  if !preserveFailureWindow { updateWindow?.orderOut(nil) }
 }
}
