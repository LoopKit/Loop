//
//  SmartwatchManagerHost.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopAlgorithm
import LoopCore
import LoopKit

/// Sends Loop's state to the watch plugin in Settings → Devices.
///
/// A new glucose reading is sent as soon as the glucose store saves it, before
/// the loop runs; the snapshot is sent again when the loop's output changes.
/// Unchanged snapshots are not resent.
@MainActor
final class SmartwatchManagerHost {
    unowned let deviceManager: DeviceDataManager
    unowned let loopDataManager: LoopDataManager
    unowned let settingsManager: SettingsManager
    let glucoseStore: GlucoseStore
    private let healthStore: HKHealthStore

    let log = DiagnosticLog(category: "SmartwatchManagerHost")

    private var lastSentSnapshot: SmartwatchStatusSnapshot?
    /// Incremented per update so a slower glucose fetch cannot overwrite a newer snapshot.
    private var updateGeneration = 0
    private var notificationObservers: [Any] = []
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
        healthStore: HKHealthStore
    ) {
        self.deviceManager = deviceManager
        self.loopDataManager = loopDataManager
        self.settingsManager = settingsManager
        self.glucoseStore = glucoseStore
        self.healthStore = healthStore

        notificationObservers = [
            // Posted as soon as new samples are saved, before LoopDataManager
            // recomputes its display state for them.
            NotificationCenter.default.addObserver(forName: GlucoseStore.glucoseSamplesDidChange, object: glucoseStore, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            },
            NotificationCenter.default.addObserver(forName: .LoopDataUpdated, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            },
            NotificationCenter.default.addObserver(forName: .HealthStorePreferredGlucoseUnitDidChange, object: healthStore, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            },
            NotificationCenter.default.addObserver(forName: .LoopCycleCompleted, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            },
            NotificationCenter.default.addObserver(forName: .SmartwatchManagerChanged, object: deviceManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ]
    }

    /// Sends the current snapshot even if unchanged, for a new watch manager or
    /// one that reconnected.
    func refresh() {
        lastSentSnapshot = nil
        loggedUndeclaredRequest = []
        update()
    }

    private func update() {
        guard let smartwatchManager = deviceManager.smartwatchManager else {
            return
        }
        retractWatchAlertsNoLongerShown(smartwatchManager)
        updateGeneration += 1
        let generation = updateGeneration
        // Fill only what the watch asks for now (the user may have turned a display
        // element off), within what the plugin declares.
        let capabilities = smartwatchManager.effectiveCapabilities
        logUndeclaredRequest(smartwatchManager)

        Task {
            let snapshot: SmartwatchStatusSnapshot
            do {
                snapshot = try await makeSnapshot(capabilities: capabilities)
            } catch {
                log.error("Unable to read glucose for the watch: %{public}@", String(describing: error))
                return
            }
            guard generation == updateGeneration,
                  let current = deviceManager.smartwatchManager, (current as AnyObject) === (smartwatchManager as AnyObject),
                  snapshot != lastSentSnapshot
            else {
                return
            }
            lastSentSnapshot = snapshot
            current.watchDataDidUpdate(snapshot)
        }
    }

    /// The glucose unit from HealthKit's stored preference, which is what Loop's own
    /// display settles on. Loop's in-memory preference starts at mg/dL until
    /// HealthKit's first answer arrives, so reading it at launch briefly sent mg/dL
    /// to the watch of a mmol/L user. Falls back to it when HealthKit can't answer,
    /// for example while protected data is unavailable.
    private func displayUnit() async -> SmartwatchGlucoseUnit {
        await preferredGlucoseUnit() == .millimolesPerLiter ? .millimolesPerLiter : .milligramsPerDeciliter
    }

    func preferredGlucoseUnit() async -> LoopUnit {
        if let hkUnit = await healthStore.cachedPreferredUnits(for: .bloodGlucose) {
            return LoopUnit(from: hkUnit)
        }
        return deviceManager.displayGlucosePreference.unit
    }

    private func makeSnapshot(capabilities: SmartwatchCapabilities) async throws -> SmartwatchStatusSnapshot {
        let historyStart = Date().addingTimeInterval(-SmartwatchStatusSnapshot.historyInterval)
        let samples = try await glucoseStore.getGlucoseSamples(start: historyStart)

        let readings = samples.map(SmartwatchGlucoseReading.init)
        var snapshot = SmartwatchStatusSnapshot(
            displayUnit: await displayUnit(),
            glucose: readings.last,
            glucoseHistory: capabilities.contains(.history) ? readings : []
        )
        if capabilities.contains(.prediction) {
            snapshot.predictedGlucose = loopDataManager.predictedGlucose?.map {
                SmartwatchPredictedGlucose(date: $0.startDate, milligramsPerDeciliter: $0.quantity.doubleValue(for: .milligramsPerDeciliter))
            }
        }
        if capabilities.contains(.loopStatus) {
            snapshot.insulinOnBoard = loopDataManager.activeInsulin?.value
            snapshot.carbsOnBoard = loopDataManager.activeCarbs?.quantity.doubleValue(for: .gram)
            snapshot.lastLoopCompleted = loopDataManager.lastLoopCompleted
            snapshot.isClosedLoop = settingsManager.loopSettings.dosingEnabled
        }
        if capabilities.contains(.therapy) {
            snapshot.therapy = currentTherapyContext()
        }
        return snapshot
    }

    /// What the algorithm is working with now, in mg/dL, with any active preset
    /// applied. Loop has no sensitivity ratio (an oref/autosens value), so that
    /// stays nil.
    private func currentTherapyContext(now: Date = Date()) -> SmartwatchTherapyContext {
        let presets = loopDataManager.temporaryPresetsManager
        var tempBasalRate: Double?
        if case .tempBasal(let dose) = deviceManager.pumpManager?.status.basalDeliveryState {
            tempBasalRate = dose.unitsPerHour
        }
        let range = presets.effectiveCorrectionRangeSchedule()?.quantityRange(at: now)
        let override = presets.scheduleOverride.flatMap { $0.isActive(at: now) ? $0 : nil }
        let presetName: String? = switch override?.context {
        case .preMeal: NSLocalizedString("Pre-Meal", comment: "Name of the pre-meal preset sent to a watch")
        case .preset(let preset): preset.name
        case .activity(let activity): activity.activityType.name
        case .custom: NSLocalizedString("Custom Preset", comment: "Name of a custom preset sent to a watch")
        case nil: nil
        }
        return SmartwatchTherapyContext(
            tempBasalRate: tempBasalRate,
            scheduledBasalRate: presets.basalRateScheduleApplyingOverrideHistory?.value(at: now),
            insulinSensitivity: presets.insulinSensitivityScheduleApplyingOverrideHistory?.quantity(at: now).doubleValue(for: .milligramsPerDeciliter),
            eventualGlucose: loopDataManager.predictedGlucose?.last?.quantity.doubleValue(for: .milligramsPerDeciliter),
            correctionRange: range.map { $0.lowerBound.doubleValue(for: .milligramsPerDeciliter)...$0.upperBound.doubleValue(for: .milligramsPerDeciliter) },
            activePresetName: presetName,
            activePresetEnd: override?.scheduledEndDate
        )
    }

    /// The undeclared capabilities a plugin last requested, so each set is logged once.
    private var loggedUndeclaredRequest: SmartwatchCapabilities = []

    /// A plugin can't obtain a capability it doesn't declare: hosts act only on
    /// `effectiveCapabilities`. Log when it asks for more, once per distinct set.
    private func logUndeclaredRequest(_ manager: SmartwatchManager) {
        let undeclared = manager.undeclaredRequestedCapabilities
        guard undeclared != loggedUndeclaredRequest else { return }
        loggedUndeclaredRequest = undeclared
        guard !undeclared.isEmpty else { return }
        deviceManager.deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: nil, type: .error, message: "The watch plugin requested capabilities it doesn't declare (\(undeclared)); they are ignored", completion: nil)
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

    /// Retracts what `watchAlertsToRetract` lists, on every update (each reading,
    /// loop cycle and reconnect). The plugin ignores alerts it doesn't have, so the
    /// host keeps no record of what it sent, and this also works after a relaunch.
    func retractWatchAlertsNoLongerShown(_ smartwatchManager: SmartwatchManager, now: Date = Date()) {
        guard type(of: smartwatchManager).capabilities.contains(.alerts) else { return }
        let alertManager = deviceManager.glucoseAlertManager
        let identifiers = Self.watchAlertsToRetract(
            configuration: alertManager.activeConfiguration(at: now),
            loopAlertsEnabled: alertManager.effectiveLoopAlertsEnabled,
            lastTestAlertAt: lastWatchTestAlertAt,
            now: now
        )
        for identifier in identifiers {
            let alertIdentifier = Alert.Identifier(managerIdentifier: GlucoseAlertManager.managerIdentifier, alertIdentifier: identifier)
            smartwatchManager.watchAlertDidRetract(SmartwatchAlertIdentifier(alertIdentifier.value))
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

extension SmartwatchGlucoseReading {
    init(_ sample: StoredGlucoseSample) {
        self.init(
            date: sample.startDate,
            milligramsPerDeciliter: sample.quantity.doubleValue(for: .milligramsPerDeciliter),
            trend: sample.trend.flatMap { SmartwatchGlucoseTrend(rawValue: $0.rawValue) },
            trendRate: sample.trendRate?.doubleValue(for: .milligramsPerDeciliterPerMinute),
            wasUserEntered: sample.wasUserEntered,
            isDisplayOnly: sample.isDisplayOnly
        )
    }
}
