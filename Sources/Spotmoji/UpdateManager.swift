import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, SPUUpdaterDelegate {
    static let probeInterval: TimeInterval = 6 * 60 * 60

    var onAvailableUpdateChanged: ((String?) -> Void)?

    private static let lastProbeDateKey = "SpotmojiLastUpdateProbeDate"
    private let defaults: UserDefaults
    private var hasStarted = false
    private var probeStartedAt: Date?

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    func probeForUpdateIfNeeded(now: Date = Date()) {
        startIfNeeded()

        guard !controller.updater.sessionInProgress else { return }
        guard beginProbeIfNeeded(now: now) else { return }

        controller.updater.checkForUpdateInformation()
    }

    func checkForUpdates() {
        startIfNeeded()
        controller.updater.checkForUpdates()
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
        finishProbe()
        onAvailableUpdateChanged?(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        finishProbe()
        onAvailableUpdateChanged?(nil)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        probeStartedAt = nil
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

    private func startIfNeeded() {
        guard !hasStarted else { return }
        _ = controller
        hasStarted = true
    }
}
