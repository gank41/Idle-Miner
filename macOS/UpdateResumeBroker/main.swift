import AppKit
MainActor.assumeIsolated {
 UpdateResumeBroker.run(hostURL:UpdateResumeBroker.hostURL(from:Bundle.main.bundleURL),base:UpdateResumeBroker.defaultBase)
}
