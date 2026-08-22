import Foundation
import OSLog
import Sparkle

@MainActor
protocol UpdateChecking: AnyObject {
    var sessionInProgress: Bool { get }
    func checkForUpdateInformation()
    func checkForUpdates()
}

extension SPUUpdater: UpdateChecking {}

@MainActor
final class UpdateManager: NSObject, SPUUpdaterDelegate {
    static let probeInterval: TimeInterval = 6 * 60 * 60

    private static let logger = Logger(
        subsystem: "com.omarshahine.Spotmoji",
        category: "Updates"
    )

    var onAvailableUpdateChanged: ((String?) -> Void)?

    private static let lastProbeDateKey = "SpotmojiLastUpdateProbeDate"
    private let defaults: UserDefaults
    private let injectedUpdater: (any UpdateChecking)?
    private var hasStarted = false
    private var pendingProbeDate: Date?
    private var probeStartedAt: Date?
    private var shouldPromptAfterProbe = false

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private var updater: any UpdateChecking {
        injectedUpdater ?? controller.updater
    }

    init(
        defaults: UserDefaults = .standard,
        updater: (any UpdateChecking)? = nil
    ) {
        self.defaults = defaults
        self.injectedUpdater = updater
        super.init()
    }

    func probeForUpdateIfNeeded(now: Date = Date()) {
        startIfNeeded()
        pendingProbeDate = now

        if injectedUpdater == nil {
            // Sparkle starts its own cycle on the run loop after initialization.
            // Queue our request behind that handoff instead of racing it.
            DispatchQueue.main.async { [weak self] in
                self?.attemptPendingProbe()
            }
        } else {
            attemptPendingProbe()
        }
    }

    func checkForUpdates() {
        startIfNeeded()
        updater.checkForUpdates()
    }

    static func shouldProbe(
        lastProbeDate: Date?,
        now: Date,
        interval: TimeInterval = probeInterval
    ) -> Bool {
        guard let lastProbeDate else { return true }
        return now.timeIntervalSince(lastProbeDate) >= interval
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordAvailableUpdate(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Self.logger.info("Spotmoji is up to date")
        onAvailableUpdateChanged?(nil)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Self.logger.error("Update check aborted: \(error.localizedDescription, privacy: .public)")
        probeStartedAt = nil
        shouldPromptAfterProbe = false
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        completeUpdateCycle()
    }

    @discardableResult
    func beginProbeIfNeeded(now: Date) -> Bool {
        let lastProbeDate = defaults.object(forKey: Self.lastProbeDateKey) as? Date
        guard probeStartedAt == nil else { return false }
        guard Self.shouldProbe(lastProbeDate: lastProbeDate, now: now) else { return false }

        probeStartedAt = now
        return true
    }

    func finishProbe(now: Date = Date()) {
        guard probeStartedAt != nil else { return }
        defaults.set(now, forKey: Self.lastProbeDateKey)
        probeStartedAt = nil
    }

    func attemptPendingProbe() {
        guard let requestedAt = pendingProbeDate else { return }
        guard !updater.sessionInProgress else {
            Self.logger.info("Deferring update probe until Sparkle's current cycle finishes")
            return
        }

        pendingProbeDate = nil
        guard beginProbeIfNeeded(now: requestedAt) else { return }

        Self.logger.info("Starting silent update discovery")
        updater.checkForUpdateInformation()
    }

    func completeUpdateCycle(now: Date = Date()) {
        let shouldPrompt = probeStartedAt != nil && shouldPromptAfterProbe
        shouldPromptAfterProbe = false
        finishProbe(now: now)

        // A request deferred during Sparkle startup gets another chance as soon
        // as that cycle reports completion.
        attemptPendingProbe()

        guard shouldPrompt else { return }
        Self.logger.info("Presenting Sparkle's focused update window")
        updater.checkForUpdates()
    }

    func recordAvailableUpdate(version: String) {
        shouldPromptAfterProbe = probeStartedAt != nil
        Self.logger.info("Found Spotmoji update \(version, privacy: .public)")
        onAvailableUpdateChanged?(version)
    }

    private func startIfNeeded() {
        guard !hasStarted else { return }
        if injectedUpdater == nil {
            _ = controller
        }
        hasStarted = true
    }
}
