import AppKit

extension MinerApp {
 @objc func checkForUpdates() {
  guard updateCheckTask==nil else { return }
  updateCheckTask=Task { [weak self] in
   guard let self else { return }
   defer { self.updateCheckTask=nil }
   var retry=true
   while retry {
    retry=false
    do {
     let manifest=try await self.updateService.check()
     let versionText=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.8"
     let buildText=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "11"
     let current=(try? ReleaseVersion(versionText,build:Int(buildText) ?? 11)) ?? (try! ReleaseVersion("1.8",build:11))
     let newer=manifest.version>current
     let same=manifest.version==current
     let alert=NSAlert()
     alert.messageText=newer ? "Idle Miner \(manifest.version.text) is available" : "Idle Miner is up to date"
     let installed="Installed: \(current.text) (build \(current.build))."
     if newer || same {
      alert.informativeText="\(installed)\nLatest: \(manifest.version.text) (build \(manifest.version.build)).\n\nDownload opens the Mac installer in your browser. Open the downloaded disk image and replace Idle Miner when you are ready. Your mining session continues during this check.\n\nSHA-256 for the downloaded disk image:\n\(manifest.macOS.sha256)\n\nThe checksum is provided for optional verification; the app does not verify or install the download."
      alert.addButton(withTitle:newer ? "Download Installer" : "Download Current Installer")
      alert.addButton(withTitle:"Release Notes")
      alert.addButton(withTitle:"Close")
     } else {
      alert.informativeText="\(installed)\nThe latest published release is \(manifest.version.text) (build \(manifest.version.build)). Your installed version is newer."
      alert.addButton(withTitle:"Release Notes");alert.addButton(withTitle:"Close")
     }
     let response=await self.presentUpdateAlert(alert)
     if newer || same {
      if response == .alertFirstButtonReturn { self.openUpdateLink(manifest.macOS.url) }
      else if response == .alertSecondButtonReturn { self.openUpdateLink(manifest.releaseNotesURL) }
     } else if response == .alertFirstButtonReturn { self.openUpdateLink(manifest.releaseNotesURL) }
    } catch is CancellationError { return }
    catch {
     let alert=NSAlert();alert.alertStyle = .warning;alert.messageText="Couldn’t Check for Updates"
     alert.informativeText="\(error.localizedDescription)\n\nCheck your internet connection and try again. Your mining session is unchanged."
     alert.addButton(withTitle:"Retry");alert.addButton(withTitle:"Close")
     retry=await self.presentUpdateAlert(alert) == .alertFirstButtonReturn
    }
   }
  }
 }
 private func presentUpdateAlert(_ alert:NSAlert)async->NSApplication.ModalResponse {
  NSApp.activate(ignoringOtherApps:true)
  if let parent=NSApp.keyWindow ?? window,parent.isVisible,parent.attachedSheet==nil {
   return await alert.beginSheetModal(for:parent)
  }
  return alert.runModal()
 }
 private func openUpdateLink(_ url:URL) {
  if !NSWorkspace.shared.open(url) {
   let alert=NSAlert();alert.messageText="Couldn’t Open Your Browser"
   alert.informativeText="Try checking for updates again after setting a default browser in System Settings."
   alert.runModal()
  }
 }
}
