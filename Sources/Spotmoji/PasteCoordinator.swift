import AppKit
import ApplicationServices
import OSLog

@MainActor
enum PasteCoordinator {
    private static let logger = Logger(
        subsystem: "com.omarshahine.Spotmoji",
        category: "Paste"
    )

    enum Result {
        case pasted
        case copiedNeedsPermission
        case copiedNoTarget
        case copiedActivationFailed
    }

    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func paste(
        _ text: String,
        into preferredTarget: NSRunningApplication?,
        completion: @escaping @MainActor (Result) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard isAccessibilityEnabled else {
            requestAccessibilityPermission()
            completion(.copiedNeedsPermission)
            return
        }
        // The picker is a non-activating panel, so its foreground application is
        // still the real destination. A direct Spotlight item may need the brief
        // post-hide lookup instead, after Spotlight returns focus to that app.
        let focusedTargetBeforeHiding = TargetAppDetector.focusedEligibleApplication()
        logger.info(
            "Focused target before hiding: \(focusedTargetBeforeHiding?.bundleIdentifier ?? "none", privacy: .public)"
        )
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard let target = TargetAppDetector.focusedEligibleApplication()
                ?? focusedTargetBeforeHiding
                ?? preferredTarget
                ?? TargetAppDetector.detect()
            else {
                logger.error("No eligible paste target")
                completion(.copiedNoTarget)
                return
            }
            logger.info(
                "Resolved paste target: \(target.bundleIdentifier ?? "none", privacy: .public), active: \(target.isActive)"
            )
            guard target.isActive || target.activate() else {
                logger.error("Could not activate paste target")
                completion(.copiedActivationFailed)
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                let source = CGEventSource(stateID: .hidSystemState)
                guard
                    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                else {
                    completion(.copiedActivationFailed)
                    return
                }
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.postToPid(target.processIdentifier)
                keyUp.postToPid(target.processIdentifier)
                logger.info("Posted Command-V to pid \(target.processIdentifier)")
                completion(.pasted)
            }
        }
    }
}
