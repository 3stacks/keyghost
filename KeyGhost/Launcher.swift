import AppKit
import os

private let log = Logger(subsystem: "com.lukeboyle.keyghost", category: "launcher")

enum Launcher {
    static func launch(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            log.error("no app installed for bundleId=\(bundleId, privacy: .public)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
            if let error {
                log.error("launch failed bundleId=\(bundleId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            } else if let app {
                log.notice("launched bundleId=\(bundleId, privacy: .public) pid=\(app.processIdentifier, privacy: .public)")
            }
        }
    }

    static func openURL(_ urlString: String, inBundleId bundleId: String?) {
        guard let url = URL(string: urlString) else {
            log.error("invalid url=\(urlString, privacy: .public)")
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        if let bundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config) { app, error in
                if let error {
                    log.error("open url failed url=\(urlString, privacy: .public) bundleId=\(bundleId, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
                } else if let app {
                    log.notice("opened url=\(urlString, privacy: .public) in bundleId=\(bundleId, privacy: .public) pid=\(app.processIdentifier, privacy: .public)")
                }
            }
        } else {
            NSWorkspace.shared.open(url)
            log.notice("opened url=\(urlString, privacy: .public) in default handler")
        }
    }
}
