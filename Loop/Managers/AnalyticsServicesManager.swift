//
//  AnalyticsServicesManager.swift
//  Loop
//
//  Created by Nathan Racklyeft on 4/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import LoopKit
import LoopCore
import HealthKit

final class AnalyticsServicesManager {

    private lazy var log = DiagnosticLog(category: "AnalyticsServicesManager")

    private var analyticsServices = [AnalyticsService]()

    var stateProvider: (() -> AnalyticsState)?

    private var lastState: AnalyticsState?

    init() {}

    func addService(_ analyticsService: AnalyticsService) {
        analyticsServices.append(analyticsService)
    }

    func restoreService(_ analyticsService: AnalyticsService) {
        analyticsServices.append(analyticsService)
    }

    func removeService(_ analyticsService: AnalyticsService) {
        analyticsServices.removeAll { $0.pluginIdentifier == analyticsService.pluginIdentifier }
    }

    private func logEvent(_ name: String, withProperties properties: [AnyHashable: Any]? = nil, outOfSession: Bool = false) {
        log.debug("%{public}@ %{public}@", name, String(describing: properties))
        analyticsServices.forEach { $0.recordAnalyticsEvent(name, withProperties: properties, outOfSession: outOfSession) }
    }

    func identify(_ property: String, value: String) {
        log.debug("Identify %{public}@: %{public}@", property, value)
        analyticsServices.forEach { $0.recordIdentify(property, value: value) }
    }

    func identify(_ property: String, array: [String]) {
        log.debug("Identify %{public}@: %{public}@", property, array)
        analyticsServices.forEach { $0.recordIdentify(property, array: array) }
    }


    // MARK: - UIApplicationDelegate

    func application(didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]?) {
        logEvent("App Launch")
    }

    func identifyAppName(_ appName: String) {
        identify("App Name", value: appName)
    }

    func identifyWorkspaceGitRevision(_ revision: String) {
        identify("Workspace Revision", value: revision)
    }

    // MARK: - Device Type
    func identifyPumpType(_ pumpType: String) {
        identify("Pump Type", value: pumpType)
    }

    func identifyCGMType(_ cgmType: String) {
        identify("CGM Type", value: cgmType)
    }

    func identifyPumpModel(_ model: String?) {
        identify("Pump Model", value: model ?? "Unknown")
    }

    func identifyCGMModel(_ model: String?) {
        identify("CGM Model", value: model ?? "Unknown")
    }

    // MARK: - Screens

    func didDisplayBolusScreen() {
        logEvent("Bolus Screen")
    }

    func didDisplayCarbEntryScreen() {
        logEvent("Carb Entry Screen")
    }

    func didDisplaySettingsScreen() {
        logEvent("Settings Screen")
    }

    func didDisplayStatusScreen() {
        logEvent("Status Screen")
    }

    // MARK: - Config Events

    func transmitterTimeDidDrift(_ drift: TimeInterval) {
        logEvent("Transmitter time change", withProperties: ["value" : drift], outOfSession: true)
    }

    func pumpTimeDidDrift(_ drift: TimeInterval) {
        logEvent("Pump time change", withProperties: ["value": drift], outOfSession: true)
    }

    func pumpBatteryWasReplaced() {
        logEvent("Pump battery replacement", outOfSession: true)
    }

    func deviceManagerDidRecordEvent(_ name: String, properties: [AnyHashable: Any]?) {
        logEvent(name, withProperties: properties, outOfSession: true)
    }

    func reservoirWasRewound() {
        logEvent("Pump reservoir rewind", outOfSession: true)
    }

    func didChangeBasalRateSchedule() {
        logEvent("Basal rate change")
    }

    func didChangeCarbRatioSchedule() {
        logEvent("Carb ratio change")
    }

    func didChangeInsulinModel() {
        logEvent("Insulin model change")
    }

    func didChangeInsulinSensitivitySchedule() {
        logEvent("Insulin sensitivity change")
    }

    func didChangeLoopSettings(from oldValue: LoopSettings, to newValue: LoopSettings) {
        if newValue.maximumBasalRatePerHour != oldValue.maximumBasalRatePerHour {
            logEvent("Maximum basal rate change")
        }

        if newValue.maximumBolus != oldValue.maximumBolus {
            logEvent("Maximum bolus change")
        }

        if newValue.suspendThreshold != oldValue.suspendThreshold {
            logEvent("Minimum BG Guard change")
        }

        if newValue.basalRateSchedule?.timeZone != oldValue.basalRateSchedule?.timeZone {
            logEvent("Therapy schedule time zone change")
        }

        if newValue.scheduleOverride != oldValue.scheduleOverride {
            logEvent("Temporary schedule override change")
        }

        if newValue.glucoseTargetRangeSchedule != oldValue.glucoseTargetRangeSchedule {
            logEvent("Glucose target range change")
        }
    }

    // MARK: - Loop Events

    func pumpWasRemoved() {
        logEvent("Pump Removed")
        identifyPumpType("None")
        identifyPumpModel("None")
    }

    func pumpWasAdded(identifier: String) {
        logEvent("Pump Added", withProperties: ["identifier" : identifier])
    }

    func cgmWasRemoved() {
        logEvent("CGM Removed")
        identifyCGMType("None")
        identifyCGMModel("None")
    }

    func cgmWasAdded(identifier: String) {
        logEvent("CGM Added", withProperties: ["identifier" : identifier])
    }

    func didAddCarbs(source: String) {
        logEvent("Carb entry created", withProperties: ["source" : source], outOfSession: source != "Phone")
    }

    func didRetryBolus() {
        logEvent("Bolus Retry")
    }

    func didBolus(source: String) {
        logEvent("Bolus set", withProperties: ["source" : source], outOfSession: source != "Phone")
    }

    // MARK: - Daily Summary

    func didStoreGlucose(_ samples: [StoredGlucoseSample]) {
        let count = samples.filter { !$0.wasUserEntered }.count
        updateDailySummary { $0.glucoseCount += count }
    }

    func loopDidSucceed(_ duration: TimeInterval) {
        updateDailySummary { summary in
            summary.loopSuccessCount += 1
            summary.totalLoopDuration += duration
            summary.maxLoopDuration = max(summary.maxLoopDuration, duration)
        }
    }

    func loopDidError(error: LoopError) {
        updateDailySummary { $0.loopErrorCounts[error.issueId, default: 0] += 1 }
    }

    func identifyState() {
        guard let state = stateProvider?() else {
            return
        }
        identify("Closed Loop", value: state.closedLoop ? "On" : "Off")
        identify("Dosing Strategy", value: state.dosingStrategy)
        identify("Integral Retrospective Correction", value: state.integralRetrospectiveCorrection ? "On" : "Off")
        identify("Glucose Based Partial Application", value: state.glucoseBasedPartialApplication ? "On" : "Off")
        lastState = state
    }

    // Callers are on the loop and CGM queues; the summary and state are only touched on main
    private func updateDailySummary(_ update: @escaping (inout AnalyticsDailySummary) -> Void) {
        let now = Date()
        DispatchQueue.main.async {
            let day = Calendar.current.startOfDay(for: now)
            var summary = UserDefaults.standard.analyticsDailySummary ?? AnalyticsDailySummary(day: day)

            if summary.day != day {
                self.logEvent("Daily summary", withProperties: summary.properties, outOfSession: true)
                summary = AnalyticsDailySummary(day: day)
            }

            update(&summary)

            if let state = self.stateProvider?() {
                summary.state = state
                if let lastState = self.lastState, state != lastState {
                    self.logStateChanges(from: lastState, to: state)
                    self.identifyState()
                }
            }

            UserDefaults.standard.analyticsDailySummary = summary
        }
    }

    private func logStateChanges(from oldState: AnalyticsState, to newState: AnalyticsState) {
        if newState.closedLoop != oldState.closedLoop {
            logEvent("Closed loop enabled change", withProperties: ["enabled": newState.closedLoop])
        }
        if newState.dosingStrategy != oldState.dosingStrategy {
            logEvent("Dosing strategy change", withProperties: ["value": newState.dosingStrategy])
        }
        if newState.integralRetrospectiveCorrection != oldState.integralRetrospectiveCorrection {
            logEvent("Algorithm experiment change", withProperties: ["experiment": "Integral Retrospective Correction", "enabled": newState.integralRetrospectiveCorrection])
        }
        if newState.glucoseBasedPartialApplication != oldState.glucoseBasedPartialApplication {
            logEvent("Algorithm experiment change", withProperties: ["experiment": "Glucose Based Partial Application", "enabled": newState.glucoseBasedPartialApplication])
        }
    }

    func didDisplayAlert(identifier: String, interruptionLevel: Alert.InterruptionLevel, scheduled: Bool) {
        logEvent("Alert Displayed", withProperties: ["identifier": identifier, "interruptionLevel": interruptionLevel.rawValue, "scheduled": scheduled], outOfSession: scheduled)
    }

    func didEnactOverride(kind: String, duration: TemporaryScheduleOverride.Duration) {
        var properties: [String: Any] = ["kind": kind]

        switch duration {
        case .finite(let interval):
            properties["durationMinutes"] = Int(interval.minutes)
        case .indefinite:
            properties["durationMinutes"] = "indefinite"
        }

        logEvent("Override Enacted", withProperties: properties)
    }

    func didEndOverride(kind: String) {
        logEvent("Override Ended", withProperties: ["kind": kind])
    }
}


// MARK: - PresetActivationObserver
extension AnalyticsServicesManager: PresetActivationObserver {
    func presetActivated(context: TemporaryScheduleOverride.Context, duration: TemporaryScheduleOverride.Duration) {
        didEnactOverride(kind: context.analyticsKind, duration: duration)
    }

    func presetDeactivated(context: TemporaryScheduleOverride.Context) {
        didEndOverride(kind: context.analyticsKind)
    }
}

extension TemporaryScheduleOverride.Context {
    var analyticsKind: String {
        switch self {
        case .legacyWorkout: return "workout"
        case .preMeal: return "preMeal"
        case .custom: return "custom"
        case .preset: return "preset"
        }
    }
}

struct AnalyticsState: Codable, Equatable {
    var closedLoop: Bool
    var dosingStrategy: String
    var integralRetrospectiveCorrection: Bool
    var glucoseBasedPartialApplication: Bool
}

struct AnalyticsDailySummary: Codable, Equatable {
    var day: Date
    var utcOffset = TimeZone.current.secondsFromGMT()
    var loopSuccessCount = 0
    var totalLoopDuration: TimeInterval = 0
    var maxLoopDuration: TimeInterval = 0
    var loopErrorCounts: [String: Int] = [:]
    var glucoseCount = 0
    var state: AnalyticsState?

    var properties: [AnyHashable: Any] {
        var properties: [AnyHashable: Any] = [
            "day": ISO8601DateFormatter.string(from: day, timeZone: TimeZone(secondsFromGMT: utcOffset) ?? .current, formatOptions: .withFullDate),
            "utcOffset": utcOffset,
            "loopSuccessCount": loopSuccessCount,
            "meanLoopDuration": loopSuccessCount > 0 ? totalLoopDuration / Double(loopSuccessCount) : 0,
            "maxLoopDuration": maxLoopDuration,
            "loopErrorCount": loopErrorCounts.values.reduce(0, +),
            "loopErrorCounts": loopErrorCounts,
            "glucoseCount": glucoseCount
        ]
        if let state {
            properties["closedLoop"] = state.closedLoop
            properties["dosingStrategy"] = state.dosingStrategy
            properties["integralRetrospectiveCorrection"] = state.integralRetrospectiveCorrection
            properties["glucoseBasedPartialApplication"] = state.glucoseBasedPartialApplication
        }
        return properties
    }
}

extension UserDefaults {
    private static let analyticsDailySummaryKey = "com.loopkit.Loop.AnalyticsDailySummary"
    private static let scheduledAlertsReportedThroughKey = "com.loopkit.Loop.AnalyticsScheduledAlertsReportedThrough"

    var scheduledAlertsReportedThrough: Date? {
        get { object(forKey: Self.scheduledAlertsReportedThroughKey) as? Date }
        set { set(newValue, forKey: Self.scheduledAlertsReportedThroughKey) }
    }

    var analyticsDailySummary: AnalyticsDailySummary? {
        get {
            data(forKey: Self.analyticsDailySummaryKey).flatMap { try? JSONDecoder().decode(AnalyticsDailySummary.self, from: $0) }
        }
        set {
            set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.analyticsDailySummaryKey)
        }
    }
}

extension AutomaticDosingStrategy {
    var analyticsValue: String {
        switch self {
        case .automaticBolus:
            return "Automatic Bolus"
        case .tempBasalOnly:
            return "Temp Basal"
        }
    }
}

