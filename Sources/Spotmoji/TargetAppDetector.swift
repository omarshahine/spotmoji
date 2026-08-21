import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum TargetAppDetector {
    private static let excludedBundleIDs: Set<String> = [
        "com.apple.Spotlight",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.loginwindow",
        "com.omarshahine.Spotmoji",
    ]

    static func detect() -> NSRunningApplication? {
        if let focused = focusedEligibleApplication() {
            return focused
        }

        // Before Spotmoji activates, AppKit still knows which regular app owned
        // the focused text field. Prefer that over window ordering because
        // screen-sharing and overlay windows can appear above the real target.
        if let frontmost = frontmostEligibleApplication() {
            return frontmost
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        for window in windows {
            guard
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0,
                let pidValue = window[kCGWindowOwnerPID as String] as? Int,
                pidValue != Int(ownPID),
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                (bounds["Width"] ?? 0) > 160,
                (bounds["Height"] ?? 0) > 80
            else { continue }

            let pid = pid_t(pidValue)
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            guard
                app.activationPolicy == .regular,
                let bundleID = app.bundleIdentifier,
                isEligible(
                    bundleIdentifier: bundleID,
                    localizedName: app.localizedName,
                    activationPolicy: app.activationPolicy
                )
            else { continue }

            return app
        }
        return nil
    }

    static func focusedEligibleApplication() -> NSRunningApplication? {
        var focusedValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedApplicationAttribute as CFString,
            &focusedValue
        )
        guard result == .success, let focusedValue else { return nil }

        let focusedElement = focusedValue as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &pid) == .success,
              let application = NSRunningApplication(processIdentifier: pid),
              isEligible(
                  bundleIdentifier: application.bundleIdentifier,
                  localizedName: application.localizedName,
                  activationPolicy: application.activationPolicy
              )
        else { return nil }
        return application
    }

    static func frontmostEligibleApplication() -> NSRunningApplication? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              isEligible(
                  bundleIdentifier: frontmost.bundleIdentifier,
                  localizedName: frontmost.localizedName,
                  activationPolicy: frontmost.activationPolicy
              )
        else { return nil }
        return frontmost
    }

    static func isEligible(
        bundleIdentifier: String?,
        localizedName: String?,
        activationPolicy: NSApplication.ActivationPolicy
    ) -> Bool {
        guard
            activationPolicy == .regular,
            let bundleIdentifier,
            !excludedBundleIDs.contains(bundleIdentifier)
        else { return false }

        let name = localizedName?.lowercased() ?? ""
        if ["spotlight", "dock", "window server", "control center", "notification center", "spotmoji"]
            .contains(name) {
            return false
        }
        return true
    }
}
