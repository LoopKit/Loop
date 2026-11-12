//
//  SmartwatchManagerHost.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Combine
import Foundation
import HealthKit
import LoopAlgorithm
import LoopCore
import LoopKit

/// The watch plugin's host in Settings → Devices: its `SmartwatchManagerDelegate`.
///
/// The plugin reads Loop's state from here after `hostDataDidChange`, which says
/// what changed. A new glucose reading is signalled as soon as the glucose store
/// saves it, before the loop runs; the loop's output when it changes.
///
/// The plugin's log lines go to the device log, and its alerts to Loop's alert
/// manager, at most time-sensitive. Its remote actions get the checks Loop applies
/// to any request of that kind (`SmartwatchManagerHost+RemoteActions.swift`).
@MainActor
final class SmartwatchManagerHost {
    unowned let deviceManager: DeviceDataManager
    unowned let loopDataManager: LoopDataManager
    unowned let settingsManager: SettingsManager
    let glucoseStore: GlucoseStore
    private let healthStore: HKHealthStore
    let deliverBolus: (Double) async throws -> Void
    let alertMuter: AlertMuter
    /// Adds grams of carbs dated when the user confirmed them on the watch.
    let deliverCarbs: (Double, Date, TimeInterval) async throws -> Void
    let startOverride: (String) async throws -> Void
    let cancelOverride: () async throws -> Void

    let log = DiagnosticLog(category: "SmartwatchManagerHost")

    /// Whether a watch bolus is being delivered, so a second one waits for its result.
    var isDeliveringWatchBolus = false
    /// The last answer to the plugin's 0 g recommendation read, which it makes
    /// after every change for its bolus context: logged only when it changes.
    var lastContextRecommendation: Double?
    /// What changed since the watch manager was last told, sent on the next main
    /// run loop turn so changes that arrive together go out as one call.
    private var pendingChanges: SmartwatchHostDataChange = []
    private var notificationObservers: [Any] = []
    private var cancellables: Set<AnyCancellable> = []
    /// The Closed Loop setting the watch was last told about.
    private var observedDosingEnabled = false
    /// When a test alert last went to the watch. Loop never retracts test alerts,
    /// so the host clears them once they have shown for `watchTestAlertDuration`.
    var lastWatchTestAlertAt: Date?
    /// How long a test alert colours the watch's ring.
    static let watchTestAlertDuration: TimeInterval = 30

    init(
        deviceManager: DeviceDataManager,
        loopDataManager: LoopDataManager,
        settingsManager: SettingsManager,
        glucoseStore: GlucoseStore,
        healthStore: HKHealthStore,
        alertMuter: AlertMuter,
        deliverBolus: @escaping (Double) async throws -> Void,
        deliverCarbs: @escaping (Double, Date, TimeInterval) async throws -> Void,
        startOverride: @escaping (String) async throws -> Void,
        cancelOverride: @escaping () async throws -> Void
    ) {
        self.deviceManager = deviceManager
        self.loopDataManager = loopDataManager
        self.settingsManager = settingsManager
        self.glucoseStore = glucoseStore
        self.healthStore = healthStore
        self.deliverBolus = deliverBolus
        self.alertMuter = alertMuter
        self.deliverCarbs = deliverCarbs
        self.startOverride = startOverride
        self.cancelOverride = cancelOverride

        notificationObservers = [
            // Posted as soon as new samples are saved, before LoopDataManager
            // recomputes its display state for them.
            NotificationCenter.default.addObserver(forName: GlucoseStore.glucoseSamplesDidChange, object: glucoseStore, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.signal(.glucose) }
            },
            NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: nil, queue: .main) { [weak self] note in
                let context = (note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopUpdateContext.RawValue).flatMap(LoopUpdateContext.init(rawValue:))
                MainActor.assumeIsolated {
                    // Preferences cover settings, presets and the active override,
                    // and closed loop, which the loop state reports.
                    self?.signal(context == .preferences ? [.loop, .presets, .settings] : .loop)
                }
            },
            NotificationCenter.default.addObserver(forName: .HealthStorePreferredGlucoseUnitDidChange, object: healthStore, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.signal(.settings) }
            },
            NotificationCenter.default.addObserver(forName: .LoopCycleCompleted, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.signal(.loop) }
            },
            // The pump's bolus volumes.
            NotificationCenter.default.addObserver(forName: .PumpManagerChanged, object: deviceManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.signal(.settings) }
            },
        ]

        alertMuter.$configuration
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.signal(.alertMute) }
            .store(in: &cancellables)

        // A manual temp basal turns automatic dosing off, and its end turns it back on.
        deviceManager.$pumpIsAllowingAutomation
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.signal(.loop) }
            .store(in: &cancellables)

        // The Closed Loop switch sets the setting directly and posts no
        // LoopDataUpdated, so it is observed here, as Loop's status screen does.
        observedDosingEnabled = settingsManager.dosingEnabled
        withObservationTracking(of: settingsManager.dosingEnabled) { [weak self] enabled in
            Task { @MainActor in
                guard let self, Self.isNewDosingEnabled(enabled, last: &self.observedDosingEnabled) else {
                    return
                }
                self.signal(.loop)
            }
        }

        // The glucose display limits: a changed alert profile, or another one active.
        let glucoseAlertManager = deviceManager.glucoseAlertManager
        glucoseAlertManager.$profiles
            .dropFirst()
            .map { _ in () }
            .merge(with: glucoseAlertManager.$activeProfileID.dropFirst().removeDuplicates().map { _ in () })
            .sink { [weak self] in self?.signal(.settings) }
            .store(in: &cancellables)
    }

    /// Whether the Closed Loop setting differs from the one the watch was last
    /// told about; records it when it does.
    static func isNewDosingEnabled(_ enabled: Bool, last: inout Bool) -> Bool {
        guard enabled != last else {
            return false
        }
        last = enabled
        return true
    }

    /// Tells the watch manager that everything changed: for a new watch manager,
    /// right after its delegate is set, or one that finished onboarding.
    func refresh() {
        pendingChanges = []
        guard let smartwatchManager = deviceManager.smartwatchManager else {
            return
        }
        retractWatchAlertsNoLongerShown(smartwatchManager)
        smartwatchManager.hostDataDidChange(.all)
    }

    /// Tells the watch manager what changed, on the next main run loop turn
    /// together with whatever else changes until then.
    func signal(_ changes: SmartwatchHostDataChange) {
        let isScheduled = !pendingChanges.isEmpty
        pendingChanges.formUnion(changes)
        guard !isScheduled else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.sendPendingChanges() }
        }
    }

    private func sendPendingChanges() {
        let changes = pendingChanges
        pendingChanges = []
        guard !changes.isEmpty, let smartwatchManager = deviceManager.smartwatchManager else {
            return
        }
        retractWatchAlertsNoLongerShown(smartwatchManager)
        smartwatchManager.hostDataDidChange(changes)
    }

    /// Whether `manager` is the watch manager in Settings → Devices. Only its
    /// requests are acted on; a removed one may still hold this host.
    func isCurrentWatch(_ manager: SmartwatchManager) -> Bool {
        deviceManager.smartwatchManager.map { ($0 as AnyObject) === (manager as AnyObject) } ?? false
    }

    /// The glucose unit from HealthKit's stored preference, which is what Loop's own
    /// display settles on. Loop's in-memory preference starts at mg/dL until
    /// HealthKit's first answer arrives, so reading it at launch briefly sent mg/dL
    /// to the watch of a mmol/L user. Falls back to it when HealthKit can't answer,
    /// for example while protected data is unavailable.
    func preferredGlucoseUnit() async -> LoopUnit {
        if let hkUnit = await healthStore.cachedPreferredUnits(for: .bloodGlucose) {
            return LoopUnit(from: hkUnit)
        }
        return deviceManager.displayGlucosePreference.unit
    }

    /// A watch plugin's alert as Loop issues it: from the plugin, whatever manager
    /// it names, so it can't retract or impersonate another device's alert, and at
    /// most time-sensitive. A watch plugin's alerts are about the watch (a missing
    /// companion app); they never break through Focus or the silent switch.
    static func watchPluginAlert(_ alert: Alert, from pluginIdentifier: String) -> Alert {
        Alert(
            identifier: watchPluginAlertIdentifier(alert.identifier, from: pluginIdentifier),
            foregroundContent: alert.foregroundContent,
            backgroundContent: alert.backgroundContent,
            trigger: alert.trigger,
            interruptionLevel: alert.interruptionLevel == .critical ? .timeSensitive : alert.interruptionLevel,
            sound: alert.sound,
            metadata: alert.metadata,
            categoryIdentifier: alert.categoryIdentifier
        )
    }

    static func watchPluginAlertIdentifier(_ identifier: Alert.Identifier, from pluginIdentifier: String) -> Alert.Identifier {
        Alert.Identifier(managerIdentifier: pluginIdentifier, alertIdentifier: identifier.alertIdentifier)
    }

    /// Which glucose alert this is, so plugins needn't know Loop's alert identifiers.
    /// A test alert counts as its alarm's, so the watch shows and buzzes it the same way.
    static func glucoseAlertType(of identifier: Alert.Identifier) -> SmartwatchGlucoseAlertType? {
        guard identifier.managerIdentifier == GlucoseAlertManager.managerIdentifier else { return nil }
        switch GlucoseAlarmKind.kind(forAlertIdentifier: identifier.alertIdentifier) {
        case .urgentLow: return .urgentLow
        case .low: return .low
        case .high: return .high
        case .predictedLow: return .predictedLow
        case nil: return nil
        }
    }

    static func isTestAlert(_ identifier: Alert.Identifier) -> Bool {
        identifier.managerIdentifier == GlucoseAlertManager.managerIdentifier
            && GlucoseAlarmKind.allCases.contains { $0.testAlertIdentifier == identifier.alertIdentifier }
    }

    /// Glucose alerts the watch must stop showing although Loop won't retract them:
    /// Loop clears an alert only on a reading back over its recovery line, and stops
    /// checking one that is switched off. So every alarm that is off in the active
    /// profile, or all of them while Loop's alerts are off (the CGM raises its own),
    /// and test alerts once they have shown long enough. Based on the settings, not
    /// the reading: recovery while an alarm is on is Loop's own.
    static func watchAlertsToRetract(configuration: GlucoseAlertConfiguration, loopAlertsEnabled: Bool, lastTestAlertAt: Date?, now: Date) -> [Alert.AlertIdentifier] {
        var identifiers = GlucoseAlarmKind.allCases
            .filter { !loopAlertsEnabled || !isEnabled($0, in: configuration) }
            .map(\.alertIdentifier)
        if lastTestAlertAt.map({ now.timeIntervalSince($0) >= watchTestAlertDuration }) ?? true {
            identifiers += GlucoseAlarmKind.allCases.map(\.testAlertIdentifier)
        }
        return identifiers
    }

    private static func isEnabled(_ kind: GlucoseAlarmKind, in configuration: GlucoseAlertConfiguration) -> Bool {
        switch kind {
        case .urgentLow: return configuration.urgentLowEnabled
        case .low: return configuration.lowEnabled
        case .high: return configuration.highEnabled
        case .predictedLow: return configuration.predictedLowEnabled
        }
    }

    /// Retracts what `watchAlertsToRetract` lists, on every change signal (each
    /// reading, loop cycle and new manager). The plugin ignores alerts it doesn't
    /// have, so the host keeps no record of what it sent, and this also works after
    /// a relaunch.
    func retractWatchAlertsNoLongerShown(_ smartwatchManager: SmartwatchManager, now: Date = Date()) {
        let alertManager = deviceManager.glucoseAlertManager
        let identifiers = Self.watchAlertsToRetract(
            configuration: alertManager.activeConfiguration(at: now),
            loopAlertsEnabled: alertManager.effectiveLoopAlertsEnabled,
            lastTestAlertAt: lastWatchTestAlertAt,
            now: now
        )
        for identifier in identifiers {
            smartwatchManager.watchAlertDidRetract(Alert.Identifier(managerIdentifier: GlucoseAlertManager.managerIdentifier, alertIdentifier: identifier))
        }
    }

    /// Writes an alert note to the device log and, unless `showInPluginLog` is
    /// false, hands it to the plugin so its own log shows it next to the watch traffic.
    func logAlert(_ manager: SmartwatchManager, _ message: String, showInPluginLog: Bool = true) {
        deviceManager.deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: nil, type: .delegate, message: message, completion: nil)
        if showInPluginLog {
            manager.watchHostDidLog(message)
        }
    }
}

// MARK: - SmartwatchManagerDelegate: state and reads

extension SmartwatchManagerHost: SmartwatchManagerDelegate {
    nonisolated
    func smartwatchManagerDidUpdateState(_ manager: SmartwatchManager) {
        Task { @MainActor in
            // A removed manager must not bring its saved state back.
            guard isCurrentWatch(manager) else { return }
            deviceManager.rawSmartwatchManager = manager.rawValue
        }
    }

    func smartwatchManagerWantsDeletion(_ manager: SmartwatchManager) async {
        log.default("Watch manager with identifier '%{public}@' wants deletion", manager.pluginIdentifier)
        guard isCurrentWatch(manager) else { return }
        deviceManager.smartwatchManager = nil
    }

    func smartwatchManagerGlucoseDisplayUnit(_ manager: SmartwatchManager) async -> LoopUnit {
        await preferredGlucoseUnit()
    }

    func smartwatchManager(_ manager: SmartwatchManager, glucoseSamplesSince date: Date) async throws -> [StoredGlucoseSample] {
        try await glucoseStore.getGlucoseSamples(start: date)
    }

    /// Read together from LoopDataManager's display state, so they come from one
    /// loop run. Loop has no sensitivity ratio (an oref/autosens value), so that
    /// stays nil; eventual glucose is the end of the forecast.
    func smartwatchManagerLoopState(_ manager: SmartwatchManager) async -> SmartwatchLoopState {
        let predictedGlucose = loopDataManager.predictedGlucose ?? []
        return SmartwatchLoopState(
            lastLoopCompleted: loopDataManager.lastLoopCompleted,
            // As Loop's loop icon, Apple Watch app and widget show it: closed only while
            // Loop doses automatically, so not during a manual temp basal.
            isClosedLoop: deviceManager.isAutomaticDosingActive,
            insulinOnBoard: loopDataManager.activeInsulin,
            carbsOnBoard: loopDataManager.activeCarbs,
            predictedGlucose: Self.forecastCurves(predictedGlucose),
            eventualGlucose: predictedGlucose.last?.quantity
        )
    }

    /// Loop makes one forecast: one curve, or none before the loop has run.
    static func forecastCurves(_ forecast: [PredictedGlucoseValue]) -> [[PredictedGlucoseValue]] {
        forecast.isEmpty ? [] : [forecast]
    }

    func smartwatchManagerScheduledBasalRate(_ manager: SmartwatchManager) async -> LoopQuantity? {
        guard let schedule = loopDataManager.temporaryPresetsManager.basalRateScheduleApplyingOverrideHistory else {
            return nil
        }
        return LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: schedule.value(at: Date()))
    }

    func smartwatchManagerTempBasal(_ manager: SmartwatchManager) async -> DoseEntry? {
        guard case .tempBasal(let dose) = deviceManager.pumpManager?.status.basalDeliveryState else {
            return nil
        }
        return dose
    }

    func smartwatchManagerInsulinSensitivity(_ manager: SmartwatchManager) async -> LoopQuantity? {
        loopDataManager.temporaryPresetsManager.insulinSensitivityScheduleApplyingOverrideHistory?.quantity(at: Date())
    }

    func smartwatchManagerCorrectionRange(_ manager: SmartwatchManager) async -> ClosedRange<LoopQuantity>? {
        loopDataManager.temporaryPresetsManager.effectiveCorrectionRangeSchedule()?.quantityRange(at: Date())
    }

    /// Loop has no display limits of its own: the low and high of the active
    /// glucose alert profile, whether or not those alerts are on.
    func smartwatchManagerGlucoseDisplayLimits(_ manager: SmartwatchManager) async -> SmartwatchGlucoseDisplayLimits? {
        Self.displayLimits(from: deviceManager.glucoseAlertManager.activeConfiguration())
    }

    static func displayLimits(from configuration: GlucoseAlertConfiguration) -> SmartwatchGlucoseDisplayLimits? {
        SmartwatchGlucoseDisplayLimits(
            low: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: configuration.lowThresholdMgDL),
            high: LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: configuration.highThresholdMgDL)
        )
    }

    func smartwatchManagerOverridePresets(_ manager: SmartwatchManager) async -> [TemporaryPreset] {
        settingsManager.settings.overridePresets
    }

    /// Any running override: a preset, pre-meal, an activity or a custom one.
    func smartwatchManagerActiveOverride(_ manager: SmartwatchManager) async -> TemporaryScheduleOverride? {
        loopDataManager.temporaryPresetsManager.activeOverride
    }

    func smartwatchManagerAlertMuteEnd(_ manager: SmartwatchManager) async -> Date? {
        alertMuter.configuration.shouldMute ? alertMuter.configuration.mutingEndTime : nil
    }

    func smartwatchManagerMaximumBolus(_ manager: SmartwatchManager) async -> Double? {
        settingsManager.loopSettings.maximumBolus
    }

    func smartwatchManagerMaximumCarbEntry(_ manager: SmartwatchManager) async -> Double? {
        LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram)
    }

    func smartwatchManagerSupportedBolusVolumes(_ manager: SmartwatchManager) async -> [Double] {
        deviceManager.pumpManager?.supportedBolusVolumes ?? []
    }

    /// Loop's fast, medium and slow, as in carb entry.
    func smartwatchManagerDefaultCarbAbsorptionTimes(_ manager: SmartwatchManager) async -> (fast: TimeInterval, medium: TimeInterval, slow: TimeInterval)? {
        LoopCoreConstants.defaultCarbAbsorptionTimes
    }
}

// MARK: - DeviceManagerDelegate: the plugin's log and alerts

extension SmartwatchManagerHost {
    nonisolated
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        Task { @MainActor in
            deviceManager.deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: deviceIdentifier, type: type, message: message, completion: completion)
        }
    }

    nonisolated
    func deviceManager(_ manager: DeviceManager, recordAnalyticsEvent name: String, properties: [AnyHashable: Any]?) {
        Task { @MainActor in
            deviceManager.deviceManager(manager, recordAnalyticsEvent: name, properties: properties)
        }
    }

    /// Issues the plugin's alert about the watch as Loop's own alert from this
    /// plugin, capped by `watchPluginAlert`.
    func issueAlert(_ alert: Alert) async {
        guard let manager = deviceManager.smartwatchManager else {
            return
        }
        let watchAlert = Self.watchPluginAlert(alert, from: manager.pluginIdentifier)
        let content = watchAlert.foregroundContent ?? watchAlert.backgroundContent
        var note = "Watch plugin alert: \(content.title): \(content.body)"
        if alert.interruptionLevel != watchAlert.interruptionLevel {
            note += " (critical lowered to time-sensitive)"
        }
        if alert.identifier != watchAlert.identifier {
            note += " (issued as \(watchAlert.identifier.value), not \(alert.identifier.value))"
        }
        deviceManager.deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: nil, type: .error, message: note, completion: nil)
        await deviceManager.alertManager?.issueAlert(watchAlert)
    }

    func retractAlert(identifier: Alert.Identifier) async {
        guard let manager = deviceManager.smartwatchManager else {
            return
        }
        await deviceManager.alertManager?.retractAlert(identifier: Self.watchPluginAlertIdentifier(identifier, from: manager.pluginIdentifier))
    }

    // The lookups find the plugin's alerts where `issueAlert` stored them: under
    // the plugin's identifier, whatever manager the plugin names.

    func doesIssuedAlertExist(identifier: Alert.Identifier) async throws -> Bool {
        guard let manager = deviceManager.smartwatchManager else {
            return false
        }
        return try await deviceManager.doesIssuedAlertExist(identifier: Self.watchPluginAlertIdentifier(identifier, from: manager.pluginIdentifier))
    }

    func lookupAllUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        guard let manager = deviceManager.smartwatchManager else {
            return []
        }
        return try await deviceManager.lookupAllUnretracted(managerIdentifier: manager.pluginIdentifier)
    }

    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String) async throws -> [PersistedAlert] {
        guard let manager = deviceManager.smartwatchManager else {
            return []
        }
        return try await deviceManager.lookupAllUnacknowledgedUnretracted(managerIdentifier: manager.pluginIdentifier)
    }

    func recordRetractedAlert(_ alert: Alert, at date: Date) async throws {
        guard let manager = deviceManager.smartwatchManager else {
            return
        }
        try await deviceManager.recordRetractedAlert(Self.watchPluginAlert(alert, from: manager.pluginIdentifier), at: date)
    }
}
