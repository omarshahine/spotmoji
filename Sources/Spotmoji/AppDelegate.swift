import AppKit
import CoreSpotlight

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var picker: PickerWindowController?
    private var targetApp: NSRunningApplication?
    private var itemsBySpotlightIdentifier: [String: EmojiItem] = [:]
    private var handledInitialSpotlightActivity = false
    private var awaitingInitialSpotlightActivity = false
    private var pendingSpotlightQuery: String?
    private var pendingSpotlightItemIdentifier: String?
    private let updateManager = UpdateManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let items = try EmojiStore.load()
            itemsBySpotlightIdentifier = Dictionary(
                uniqueKeysWithValues: items.map { (EmojiSpotlightIndex.identifier(for: $0), $0) }
            )
            EmojiSpotlightIndex.indexIfNeeded(items)
            picker = PickerWindowController(
                items: items,
                onChoose: { [weak self] item in self?.choose(item) },
                onCancel: { NSApp.terminate(nil) },
                onCheckForUpdates: { [weak self] in self?.updateManager.checkForUpdates() }
            )
            updateManager.onAvailableUpdateChanged = { [weak self] version in
                self?.picker?.showAvailableUpdate(version: version)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Emoji data could not be loaded"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        targetApp = TargetAppDetector.detect()
        if !PasteCoordinator.isAccessibilityEnabled {
            PasteCoordinator.requestAccessibilityPermission()
        }
        presentPendingSpotlightActivityIfReady()
        // LaunchServices can announce a continuation without ever delivering it.
        // Wait briefly so real Spotlight actions stay invisible, then fall back to
        // the picker for an ordinary launch or an abandoned continuation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.handledInitialSpotlightActivity else { return }
            self.awaitingInitialSpotlightActivity = false
            self.presentPicker()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        targetApp = TargetAppDetector.detect()
        presentPicker()
        return true
    }

    func application(
        _ application: NSApplication,
        willContinueUserActivityWithType userActivityType: String
    ) -> Bool {
        guard
            userActivityType == CSQueryContinuationActionType
                || userActivityType == CSSearchableItemActionType
        else { return false }
        awaitingInitialSpotlightActivity = true
        return true
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        switch userActivity.activityType {
        case CSQueryContinuationActionType:
            guard let query = userActivity.userInfo?[CSSearchQueryString] as? String else { return false }
            pendingSpotlightQuery = query
        case CSSearchableItemActionType:
            guard
                let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String
            else { return false }
            pendingSpotlightItemIdentifier = identifier
        default:
            return false
        }

        handledInitialSpotlightActivity = true
        awaitingInitialSpotlightActivity = false
        targetApp = TargetAppDetector.detect()
        presentPendingSpotlightActivityIfReady()
        return true
    }

    func application(
        _ application: NSApplication,
        didFailToContinueUserActivityWithType userActivityType: String,
        error: any Error
    ) {
        guard
            userActivityType == CSQueryContinuationActionType
                || userActivityType == CSSearchableItemActionType
        else { return }
        handledInitialSpotlightActivity = false
        awaitingInitialSpotlightActivity = false
        pendingSpotlightQuery = nil
        pendingSpotlightItemIdentifier = nil
        targetApp = TargetAppDetector.detect()
        presentPicker()
    }

    private func presentPendingSpotlightActivityIfReady() {
        guard picker != nil else { return }

        if let identifier = pendingSpotlightItemIdentifier {
            pendingSpotlightItemIdentifier = nil
            if let item = itemsBySpotlightIdentifier[identifier] {
                choose(item)
            } else {
                presentPicker()
            }
            return
        }

        if let query = pendingSpotlightQuery {
            pendingSpotlightQuery = nil
            presentPicker(searchQuery: query)
        }
    }

    private func presentPicker(searchQuery: String = "") {
        picker?.showPicker(searchQuery: searchQuery)
        updateManager.probeForUpdateIfNeeded()
    }

    private func choose(_ item: EmojiItem) {
        PasteCoordinator.paste(item.emoji, into: targetApp) { [weak self] result in
            switch result {
            case .pasted:
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    NSApp.terminate(nil)
                }
            case .copiedNeedsPermission:
                self?.presentPicker(searchQuery: item.name)
                self?.picker?.showMessage("Copied \(item.emoji). Allow Accessibility, then choose it again to paste directly.")
            case .copiedNoTarget:
                self?.presentPicker(searchQuery: item.name)
                self?.picker?.showMessage("Copied \(item.emoji). I couldn't identify the previous app.")
            case .copiedActivationFailed:
                self?.presentPicker(searchQuery: item.name)
                self?.picker?.showMessage("Copied \(item.emoji). The previous app could not be activated.")
            }
        }
    }
}
