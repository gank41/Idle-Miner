import AppKit
MainActor.assumeIsolated {
 let application=NSApplication.shared
 let delegate=MinerApp()
 application.delegate=delegate
 application.setActivationPolicy(.accessory)
 withExtendedLifetime(delegate) { application.run() }
}
