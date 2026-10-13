#if LUPED_PEBBLE
import Combine
import Foundation
import LoopAlgorithm
import LoopKit
import LoopKitUI
import LupedKit

/// Loop's adapter for LupedKit, which owns the Luped watch link, payload,
/// delivery and Settings → Devices → Pebble state.
///
/// It supplies Loop's stored CGM readings in Loop's display unit, the active
/// glucose alert profile and Loop's alert mute, and asks LupedKit to re-send
/// whenever any of them change.
@MainActor
final class LupedPebbleTransport {
    static let shared = LupedPebbleTransport()

    private let luped = LupedTransport(hostName: "Loop")
    private let log = DiagnosticLog(category: "LupedPebbleTransport")

    /// The watch communication log shown in Settings → Devices → Pebble.
    var communicationLog: LupedCommunicationLog { luped.communicationLog }
    /// Live link state and watch diagnostics for Settings → Devices → Pebble.
    var status: LupedLinkStatus { luped.status }

    private var glucoseStore: GlucoseStore?
    private weak var glucoseAlertManager: GlucoseAlertManager?
    private weak var alertMuter: AlertMuter?
    private var unit = LoopUnit.milligramsPerDeciliter
    private var observers: Set<AnyCancellable> = []

    private init() {
        luped.diagnosticLog = { [log] kind, message in
            if kind == .error {
                log.error("luped: %{public}@", message)
            } else {
                log.default("luped: %{public}@", message)
            }
        }
        luped.snapshotProvider = { [weak self] in
            try await self?.snapshot()
        }
    }

    /// Starts the GATT service if needed and sends the latest stored CGM readings
    /// in Loop's display unit with the active glucose alert settings, re-sending
    /// them whenever the unit, those settings or Loop's alert mute change.
    func publish(from glucoseStore: GlucoseStore, displayGlucosePreference: DisplayGlucosePreference, glucoseAlertManager: GlucoseAlertManager, alertMuter: AlertMuter?) async {
        luped.start()
        self.glucoseStore = glucoseStore
        self.glucoseAlertManager = glucoseAlertManager
        self.alertMuter = alertMuter
        if observers.isEmpty {
            // Loop starts in mg/dL and switches to the HealthKit unit once it has loaded.
            displayGlucosePreference.$unit
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] unit in
                    guard let self else { return }
                    self.unit = unit
                    Task { await self.luped.refresh() }
                }
                .store(in: &observers)
            // These publish before the new value is stored; the Task reads it afterwards.
            Publishers.Merge4(
                glucoseAlertManager.$profiles.dropFirst().map { _ in () },
                glucoseAlertManager.$activeProfileID.dropFirst().map { _ in () },
                glucoseAlertManager.$cgmProvidesOwnAlerts.dropFirst().map { _ in () },
                glucoseAlertManager.$loopAlertsOverrideForOwnAlertingCGM.dropFirst().map { _ in () }
            )
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                Task { await self.luped.refresh() }
            }
            .store(in: &observers)
            // Muting and its timed end republish, restoring the watch's alarms.
            alertMuter?.$configuration
                .dropFirst()
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self else { return }
                    Task { await self.luped.refresh() }
                }
                .store(in: &observers)
        }
        unit = displayGlucosePreference.unit
        await luped.refresh()
    }

    /// Pushes the current reading now, re-sending it even if already delivered.
    func sendNow() {
        luped.sendNow()
    }

    /// Asks Luped for its diagnostics snapshot (battery and counters).
    func requestDiagnostics() {
        luped.requestDiagnostics()
    }

    private func snapshot() async throws -> LupedSnapshot? {
        guard let glucoseStore else {
            return nil
        }
        let samples = try await glucoseStore.getGlucoseSamples(start: Date(timeIntervalSinceNow: -LupedPayload.historyInterval))
        let readings = samples
            .filter { !$0.wasUserEntered && !$0.isDisplayOnly }
            .map { sample in
                LupedReading(
                    date: sample.startDate,
                    milligramsPerDeciliter: sample.quantity.doubleValue(for: .milligramsPerDeciliter),
                    trend: sample.trend.map(LupedTrend.init)
                )
            }
        return LupedSnapshot(
            readings: readings,
            storedSampleCount: samples.count,
            unit: unit == .millimolesPerLiter ? .millimolesPerLiter : .milligramsPerDeciliter,
            alerts: alertState()
        )
    }

    /// Loop's active glucose alert profile and alert mute. Low and high alerts
    /// repeat only when their snooze is enabled; urgent low always repeats.
    private func alertState() -> LupedAlertState {
        let muteEnd = alertMuter.flatMap { $0.configuration.shouldMute ? $0.configuration.mutingEndTime : nil }
        guard let manager = glucoseAlertManager else {
            return LupedAlertState(configuration: nil, hostAlertsActive: false, hostMuteEnd: muteEnd)
        }
        let configuration = manager.activeConfiguration()
        return LupedAlertState(
            configuration: LupedAlertConfiguration(
                urgentLowMgDL: configuration.urgentLowThresholdMgDL,
                lowMgDL: configuration.lowThresholdMgDL,
                highMgDL: configuration.highThresholdMgDL,
                urgentLowEnabled: configuration.urgentLowEnabled,
                lowEnabled: configuration.lowEnabled,
                highEnabled: configuration.highEnabled,
                urgentLowRepeat: configuration.urgentLowRepeatInterval,
                lowRepeat: configuration.lowSnoozeEnabled ? configuration.lowRepeatInterval : nil,
                highRepeat: configuration.highSnoozeEnabled ? configuration.highRepeatInterval : nil
            ),
            hostAlertsActive: manager.effectiveLoopAlertsEnabled,
            hostMuteEnd: muteEnd
        )
    }
}

private extension LupedTrend {
    init(_ trend: GlucoseTrend) {
        switch trend {
        case .downDownDown: self = .doubleDown
        case .downDown: self = .singleDown
        case .down: self = .fortyFiveDown
        case .flat: self = .flat
        case .up: self = .fortyFiveUp
        case .upUp: self = .singleUp
        case .upUpUp: self = .doubleUp
        }
    }
}
#endif
