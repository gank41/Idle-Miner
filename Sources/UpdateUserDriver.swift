import AppKit
import Sparkle

private final class UpdateWindowContentView:NSView {
 override var isOpaque:Bool { true }
 override func draw(_ dirtyRect:NSRect) { NSColor.windowBackgroundColor.setFill();dirtyRect.fill() }
}

@MainActor final class UpdateUserDriver:NSObject,SPUUserDriver,NSWindowDelegate {
 var prepareForInstallation:(() async throws->Void)?
 var installationFailed:(()->Void)?
 var isBackgroundCheck=false
 var backgroundUpdateFound:((SUAppcastItem)->Void)?
 var automaticCheckPreferencesChanged:((Bool?,String?)->Void)?
 private(set) var selectedUpdate:SUAppcastItem?
 private(set) var state:UpdatePresentationState
 private(set) var updateWindow:NSWindow?
 private let headline=NSTextField(wrappingLabelWithString:"")
 private let versionLabel=NSTextField(wrappingLabelWithString:"")
 private let statusLabel=NSTextField(wrappingLabelWithString:"")
 private let notes=NSTextView()
 private let notesScroll=NSScrollView()
 private let notesToggle=NSButton(title:"▸ Release Notes",target:nil,action:nil)
 private var notesExpanded=false
 private var layoutExpanded:Bool?
 private let automaticChecks=NSButton(checkboxWithTitle:"Automatically check for updates",target:nil,action:nil)
 private let checkFrequency=NSPopUpButton(frame:.zero,pullsDown:false)
 private var automaticChecksEnabled=false
 private var automaticCheckFrequency="daily"
 private var headlineHeight:NSLayoutConstraint!
 private var versionHeight:NSLayoutConstraint!
 private var statusHeight:NSLayoutConstraint!
 private var toggleHeight:NSLayoutConstraint!
 private var notesHeight:NSLayoutConstraint!
 private var progressHeight:NSLayoutConstraint!
 private var toggleTop:NSLayoutConstraint!
 private var notesTop:NSLayoutConstraint!
 private var progressTop:NSLayoutConstraint!
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
 func configureAutomaticChecks(enabled:Bool,frequency:String) {
  automaticChecksEnabled=enabled;automaticCheckFrequency=frequency=="weekly" ? "weekly":"daily"
  automaticChecks.state=enabled ? .on:.off
  checkFrequency.selectItem(at:automaticCheckFrequency=="weekly" ? 1:0)
  checkFrequency.isEnabled=enabled
 }
 @objc private func automaticChecksChanged() {
  automaticChecksEnabled=automaticChecks.state == .on
  checkFrequency.isEnabled=automaticChecksEnabled
  automaticCheckPreferencesChanged?(automaticChecksEnabled,nil)
 }
 @objc private func automaticCheckFrequencyChanged() {
  automaticCheckFrequency=checkFrequency.indexOfSelectedItem==1 ? "weekly":"daily"
  automaticCheckPreferencesChanged?(nil,automaticCheckFrequency)
 }
 private func ensureWindow() {
  guard updateWindow==nil else { return }
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:280),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
  window.title="Idle Miner Update";window.contentMinSize=NSSize(width:560,height:240);window.isReleasedWhenClosed=false;window.delegate=self
  window.contentView=UpdateWindowContentView(frame:window.contentView!.bounds)
  let content=window.contentView!
  let icon=NSImageView()
  icon.image=Bundle.main.url(forResource:"IdleMiner",withExtension:"icns").flatMap(NSImage.init(contentsOf:)) ?? NSApp.applicationIconImage
  icon.imageScaling = .scaleProportionallyUpOrDown;icon.setAccessibilityIdentifier("update-app-icon");icon.setAccessibilityLabel("Idle Miner")
  headline.font = .boldSystemFont(ofSize:13);headline.textColor = .labelColor;headline.setAccessibilityIdentifier("update-headline")
  versionLabel.font = .systemFont(ofSize:13);versionLabel.textColor = .labelColor
  statusLabel.font = .systemFont(ofSize:12);statusLabel.textColor = .secondaryLabelColor;statusLabel.setAccessibilityIdentifier("update-status")
  for label in [headline,versionLabel,statusLabel] { label.setContentCompressionResistancePriority(.required,for:.vertical) }
  notes.isEditable=false;notes.isSelectable=true;notes.isRichText=false;notes.importsGraphics=false;notes.font = .systemFont(ofSize:13);notes.textContainerInset=NSSize(width:10,height:10)
  notes.textColor = .textColor;notes.backgroundColor = .textBackgroundColor
  notes.frame=NSRect(x:0,y:0,width:484,height:180);notes.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude)
  notes.autoresizingMask=[.width];notes.isVerticallyResizable=true;notes.isHorizontallyResizable=false;notes.textContainer?.widthTracksTextView=true
  notes.setAccessibilityIdentifier("update-release-notes")
  let scroll=notesScroll;scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;scroll.documentView=notes
  notesToggle.target=self;notesToggle.action=#selector(toggleReleaseNotes);notesToggle.bezelStyle = .inline;notesToggle.alignment = .left
  notesToggle.font = .boldSystemFont(ofSize:12)
  notesToggle.setAccessibilityIdentifier("update-release-notes-toggle");notesToggle.setAccessibilityLabel("Release Notes")
  progress.style = .bar;progress.minValue=0;progress.maxValue=1
  let separator=NSBox();separator.boxType = .separator
  automaticChecks.target=self;automaticChecks.action=#selector(automaticChecksChanged)
  automaticChecks.font = .systemFont(ofSize:12);automaticChecks.setAccessibilityIdentifier("update-automatic-checks")
  checkFrequency.addItems(withTitles:["Daily","Weekly"]);checkFrequency.target=self;checkFrequency.action=#selector(automaticCheckFrequencyChanged)
  checkFrequency.controlSize = .small;checkFrequency.font = .systemFont(ofSize:12)
  checkFrequency.setAccessibilityIdentifier("update-check-frequency");checkFrequency.setAccessibilityLabel("Automatic update check frequency")
  configureAutomaticChecks(enabled:automaticChecksEnabled,frequency:automaticCheckFrequency)
  installButton.target=self;installButton.action=#selector(installNow);installButton.bezelStyle = .rounded;installButton.keyEquivalent="\r";installButton.setAccessibilityIdentifier("update-install-now")
  closeButton.target=self;closeButton.action=#selector(closeUpdate);closeButton.bezelStyle = .rounded;closeButton.keyEquivalent="\u{1b}"
  for view in [icon,headline,versionLabel,statusLabel,notesToggle,scroll,progress,separator,automaticChecks,checkFrequency,installButton,closeButton] { view.translatesAutoresizingMaskIntoConstraints=false;content.addSubview(view) }
  headlineHeight=headline.heightAnchor.constraint(equalToConstant:18)
  versionHeight=versionLabel.heightAnchor.constraint(equalToConstant:34)
  statusHeight=statusLabel.heightAnchor.constraint(equalToConstant:16)
  toggleHeight=notesToggle.heightAnchor.constraint(equalToConstant:18)
  notesHeight=scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:0)
  progressHeight=progress.heightAnchor.constraint(equalToConstant:12)
  toggleTop=notesToggle.topAnchor.constraint(equalTo:statusLabel.bottomAnchor,constant:10)
  notesTop=scroll.topAnchor.constraint(equalTo:notesToggle.bottomAnchor,constant:6)
  progressTop=progress.topAnchor.constraint(equalTo:scroll.bottomAnchor,constant:12)
  compactClose=closeButton.trailingAnchor.constraint(equalTo:headline.trailingAnchor)
  availableClose=closeButton.trailingAnchor.constraint(equalTo:installButton.leadingAnchor,constant:-10)
  NSLayoutConstraint.activate([
   icon.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:22),icon.topAnchor.constraint(equalTo:content.topAnchor,constant:22),icon.widthAnchor.constraint(equalToConstant:64),icon.heightAnchor.constraint(equalToConstant:64),
   headline.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:108),headline.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-22),headline.topAnchor.constraint(equalTo:content.topAnchor,constant:24),headlineHeight,
   versionLabel.leadingAnchor.constraint(equalTo:headline.leadingAnchor),versionLabel.trailingAnchor.constraint(equalTo:headline.trailingAnchor),versionLabel.topAnchor.constraint(equalTo:headline.bottomAnchor,constant:8),versionHeight,
   statusLabel.leadingAnchor.constraint(equalTo:headline.leadingAnchor),statusLabel.trailingAnchor.constraint(equalTo:headline.trailingAnchor),statusLabel.topAnchor.constraint(equalTo:versionLabel.bottomAnchor,constant:8),statusHeight,
   notesToggle.leadingAnchor.constraint(equalTo:headline.leadingAnchor),notesToggle.trailingAnchor.constraint(lessThanOrEqualTo:headline.trailingAnchor),toggleTop,toggleHeight,
   scroll.leadingAnchor.constraint(equalTo:headline.leadingAnchor),scroll.trailingAnchor.constraint(equalTo:headline.trailingAnchor),notesTop,notesHeight,
   progress.leadingAnchor.constraint(equalTo:headline.leadingAnchor),progress.trailingAnchor.constraint(equalTo:headline.trailingAnchor),progressTop,progressHeight,
   separator.leadingAnchor.constraint(equalTo:headline.leadingAnchor),separator.trailingAnchor.constraint(equalTo:headline.trailingAnchor),separator.topAnchor.constraint(equalTo:progress.bottomAnchor,constant:16),separator.heightAnchor.constraint(equalToConstant:1),
   automaticChecks.leadingAnchor.constraint(equalTo:headline.leadingAnchor),automaticChecks.topAnchor.constraint(equalTo:separator.bottomAnchor,constant:12),automaticChecks.heightAnchor.constraint(equalToConstant:20),
   checkFrequency.trailingAnchor.constraint(equalTo:headline.trailingAnchor),checkFrequency.leadingAnchor.constraint(greaterThanOrEqualTo:automaticChecks.trailingAnchor,constant:12),checkFrequency.centerYAnchor.constraint(equalTo:automaticChecks.centerYAnchor),checkFrequency.widthAnchor.constraint(equalToConstant:88),
   installButton.trailingAnchor.constraint(equalTo:headline.trailingAnchor),installButton.topAnchor.constraint(equalTo:automaticChecks.bottomAnchor,constant:16),installButton.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-18),
   availableClose,closeButton.centerYAnchor.constraint(equalTo:installButton.centerYAnchor)
  ])
  window.center();updateWindow=window
 }
 private var compactClose:NSLayoutConstraint!
 private var availableClose:NSLayoutConstraint!
 @objc private func toggleReleaseNotes() { notesExpanded.toggle();updateNotesLayout() }
 func windowDidResize(_ notification:Notification) { updateNotesLayout() }
 private func updateNotesLayout() {
  guard let window=updateWindow else { return }
  let hasNotes = !notes.string.isEmpty
  let expanded=hasNotes && notesExpanded
  notesToggle.isHidden = !hasNotes
  notesToggle.title=expanded ? "▾ Release Notes":"▸ Release Notes"
  notesToggle.setAccessibilityValue(expanded ? "Expanded":"Collapsed")
  notesScroll.isHidden = !expanded
  let width=max(1,(window.contentView?.bounds.width ?? 620)-130)
  func textHeight(_ label:NSTextField)->CGFloat {
   ceil(label.cell?.cellSize(forBounds:NSRect(x:0,y:0,width:width,height:CGFloat.greatestFiniteMagnitude)).height ?? 18)
  }
  headlineHeight.constant=textHeight(headline);versionHeight.constant=textHeight(versionLabel);statusHeight.constant=textHeight(statusLabel)
  toggleHeight.constant=hasNotes ? 18:0;toggleTop.constant=hasNotes ? 10:0
  notesTop.constant=expanded ? 6:0;notesHeight.constant=expanded ? 180:0
  progressTop.constant=progress.isHidden ? 0:12;progressHeight.constant=progress.isHidden ? 0:12
  // Minimum height follows wrapped text, including detailed errors, at this width.
  let minimumHeight=24+headlineHeight.constant+8+versionHeight.constant+8+statusHeight.constant+toggleTop.constant+toggleHeight.constant+notesTop.constant+notesHeight.constant+progressTop.constant+progressHeight.constant+16+1+12+20+16+32+18
  window.contentMinSize=NSSize(width:560,height:minimumHeight)
  guard layoutExpanded != expanded || (window.contentView?.bounds.height ?? 0)<minimumHeight else { return }
  layoutExpanded=expanded
  let old=window.frame
  var frame=window.frameRect(forContentRect:NSRect(x:0,y:0,width:window.contentView?.bounds.width ?? 620,height:minimumHeight))
  frame.origin=NSPoint(x:old.minX,y:old.maxY-frame.height)
  window.setFrame(frame,display:true)
 }
 private func render(_ status:String) {
  ensureWindow()
  switch state.phase {
  case .checking: headline.stringValue="Checking for Idle Miner updates…"
  case .available: headline.stringValue="A new version of Idle Miner is available!"
  case .downloading: headline.stringValue="Downloading Idle Miner…"
  case .extracting,.preparing: headline.stringValue="Preparing the Idle Miner update…"
  case .installing: headline.stringValue="Installing Idle Miner…"
  case .finished: headline.stringValue=status.hasPrefix("Idle Miner is up to date") ? "Idle Miner is up to date!":"Idle Miner Update"
  }
  if state.phase == .available {
   versionLabel.stringValue="Idle Miner \(state.latestVersion ?? "") is available. You have \(state.installedVersion)."
  } else {
   versionLabel.stringValue="Installed: \(state.installedVersion)   Latest: \(state.latestVersion ?? "Checking…")"
  }
  statusLabel.stringValue=status
  progress.isHidden = state.phase == .available || state.phase == .finished
  updateNotesLayout()
  installButton.isHidden=state.installButtonTitle==nil
  availableClose.isActive=false;compactClose.isActive=false
  if installButton.isHidden { compactClose.isActive=true } else { availableClose.isActive=true }
  let canClose=state.canClose && (state.phase != .downloading || cancellation != nil)
  closeButton.isEnabled=canClose
  updateWindow?.standardWindowButton(.closeButton)?.isEnabled=canClose
  showUpdateInFocus()
 }
 func showUpdateInFocus() { guard !isBackgroundCheck else { return };updateWindow?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
 private func record(_ item:SUAppcastItem) {
  selectedUpdate=item
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
  isBackgroundCheck=false;preserveFailureWindow=false;consented=false;notesExpanded=false;layoutExpanded=nil;self.cancellation=cancellation
  state.phase = .checking;state.latestVersion=nil;notes.string="";progress.isIndeterminate=true;progress.startAnimation(nil)
  render("Checking for updates…")
 }
 func showUpdateFound(with item:SUAppcastItem,state updateState:SPUUserUpdateState) async->SPUUserUpdateChoice {
  if isBackgroundCheck {
   if Self.isCompatibleBackgroundUpdate(item) { backgroundUpdateFound?(item) }
   return .dismiss
  }
  cancellation=nil;record(item);notesExpanded=true;progress.stopAnimation(nil);progress.isIndeterminate=false;progress.doubleValue=0
  if item.isInformationOnlyUpdate {
   state.phase = .finished
   await waitForAcknowledgement("This release cannot be installed on this Mac.");return .dismiss
  }
  state.phase = .available;closeChoice=updateState.stage == .installing ? .skip:.dismiss
  // Register the reply before AppKit presentation can reenter the main run loop.
  let result=await withCheckedContinuation { choice=$0;render("An update is available. Installing pauses mining and updates this copy of Idle Miner.") }
  if result == .install { return await prepareInstallation(installing:updateState.stage == .installing) }
  return result
 }
 private static func isCompatibleBackgroundUpdate(_ item:SUAppcastItem)->Bool {
  guard !item.isInformationOnlyUpdate,item.fileURL != nil else { return false }
  let version=ProcessInfo.processInfo.operatingSystemVersion
  let current="\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
  func normalized(_ raw:String)->String {
   var components=raw.split(separator:".").map(String.init)
   while components.count<3 { components.append("0") }
   return components.joined(separator:".")
  }
  if let minimum=item.minimumSystemVersion,current.compare(normalized(minimum),options:.numeric) == .orderedAscending { return false }
  if let maximum=item.maximumSystemVersion,current.compare(normalized(maximum),options:.numeric) == .orderedDescending { return false }
  return true
 }
 func showUpdateReleaseNotes(with downloadData:SPUDownloadData) {
  guard !isBackgroundCheck else { return }
  guard let text=String(data:downloadData.data.prefix(262_144),encoding:.utf8) else { return }
  notes.string=UpdateReleaseNotes.plainText(text)
 }
 func showUpdateReleaseNotesFailedToDownloadWithError(_ error:Error) {
  guard !isBackgroundCheck else { return }
  if notes.string.isEmpty { notes.string="Release notes could not be loaded." }
 }
 func showUpdateNotFoundWithError(_ error:Error) async {
  guard !isBackgroundCheck else { return }
  cancellation=nil;notesExpanded=false;layoutExpanded=nil;progress.stopAnimation(nil);state.phase = .finished
  if let item=(error as NSError).userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem { record(item) }
  if state.latestVersion==nil { state.latestVersion="Unavailable" }
  let reason=((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
  let message:String
  if reason==Int(SPUNoUpdateFoundReason.onLatestVersion.rawValue) { message="Idle Miner is up to date." }
  else if reason==Int(SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue) { message="You’re running a newer version than the latest release." }
  else { message=error.localizedDescription }
  await waitForAcknowledgement(message)
 }
 func showUpdaterError(_ error:Error) async {
  guard !isBackgroundCheck else { return }
  installationFailed?()
  cancellation=nil;notesExpanded=false;layoutExpanded=nil;progress.stopAnimation(nil);state.phase = .finished
  await waitForAcknowledgement("The update could not be completed. Your current app and preferences remain available.\n\n\(error.localizedDescription)")
 }
 private func waitForAcknowledgement(_ status:String) async { await withCheckedContinuation { acknowledgement=$0;render(status) } }
 func showDownloadInitiated(cancellation:@escaping ()->Void) {
  guard !isBackgroundCheck else { cancellation();return }
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
  guard !isBackgroundCheck else { return }
  cancellation=nil;state.phase = .extracting;progress.isIndeterminate=true;progress.startAnimation(nil)
  render("Verifying and preparing the downloaded update… macOS may ask for permission to replace this app.")
 }
 func showExtractionReceivedProgress(_ value:Double) { progress.stopAnimation(nil);progress.isIndeterminate=false;progress.doubleValue=max(0,min(1,value)) }
 func showReadyToInstallAndRelaunch() async->SPUUserUpdateChoice { await prepareInstallation() }
 private func prepareInstallation(installing:Bool=true) async->SPUUserUpdateChoice {
  guard !isBackgroundCheck,consented,let prepareForInstallation else { return .skip }
  state.phase = .preparing;render("Stopping mining and closing other Idle Miner windows…")
  do {
   try await prepareForInstallation()
   state.phase = installing ? .installing:.downloading
   render(installing ? "Installing update… Idle Miner will restore the previous currencies and Automatic mining state.":"Preparing the update download… Mining is stopped.")
   return .install
  }
  catch {
   installationFailed?()
   state.phase = .finished;preserveFailureWindow=true;render(error.localizedDescription)
   return .skip
  }
 }
 func showInstallingUpdate(withApplicationTerminated terminated:Bool,retryTerminatingApplication:@escaping ()->Void) {
  guard !isBackgroundCheck else { return }
  state.phase = .installing;render("Installing update… Idle Miner will restore the previous currencies and Automatic mining state.")
 }
 func showUpdateInstalledAndRelaunched(_ relaunched:Bool) async {
  guard !isBackgroundCheck else { return }
  state.phase = .finished
  await waitForAcknowledgement(relaunched ? "Update installed. Idle Miner has reopened with its previous currencies and Automatic mining state.":"Update installed.")
 }
 func dismissUpdateInstallation() {
  cancellation=nil
  let reply=choice;choice=nil;reply?.resume(returning:.skip)
  let ack=acknowledgement;acknowledgement=nil;ack?.resume()
  if !preserveFailureWindow { updateWindow?.orderOut(nil) }
 }
}
