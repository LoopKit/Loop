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

final class AnalyticsServicesManager {

    private lazy var log = DiagnosticLog(category: "AnalyticsServicesManager")

    private var analyticsServices = [AnalyticsService]()

    var stateProvider: (@MainActor () -> AnalyticsState)?

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

    @MainActor
    func didDisplayBolusScreen() {
        logEvent("Bolus Screen")
        updateDailySummary { $0.usage.screenCounts["bolus", default: 0] += 1 }
    }

    @MainActor
    func didDisplayCarbEntryScreen() {
        logEvent("Carb Entry Screen")
        updateDailySummary { $0.usage.screenCounts["carbEntry", default: 0] += 1 }
    }

    @MainActor
    func didDisplaySettingsScreen() {
        logEvent("Settings Screen")
        updateDailySummary { $0.usage.screenCounts["settings", default: 0] += 1 }
    }

    @MainActor
    func didDisplayStatusScreen() {
        logEvent("Status Screen")
        updateDailySummary { $0.usage.screenCounts["status", default: 0] += 1 }
    }

    // MARK: - Foreground Use

    private var foregroundStart: Date?

    private var foregroundTouchCount = 0

    @MainActor
    func didEnterForeground(at date: Date = Date()) {
        foregroundStart = date
        foregroundTouchCount = 0
    }

    @MainActor
    func didEnterBackground(at date: Date = Date()) {
        guard let foregroundStart else {
            return
        }
        self.foregroundStart = nil
        let duration = max(0, date.timeIntervalSince(foregroundStart))
        let touchCount = foregroundTouchCount
        updateDailySummary({ $0.addForegroundSession(duration: duration, touchCount: touchCount) }, now: date)
    }

    @MainActor
    func didReceiveTouch() {
        foregroundTouchCount += 1
    }

    @MainActor
    func didOpenFromNotification() {
        updateDailySummary { $0.usage.notificationOpenCount += 1 }
    }

    @MainActor
    func didOpenFromLink() {
        updateDailySummary { $0.usage.linkOpenCount += 1 }
    }

    @MainActor
    func didAcknowledgeAlert() {
        updateDailySummary { $0.usage.alertAcknowledgementCount += 1 }
    }

    // MARK: - Watch Use

    @MainActor
    func didRequestWatchContext() {
        updateDailySummary { $0.usage.watchContextRequestCount += 1 }
    }

    @MainActor
    func didAcknowledgeAlertOnWatch() {
        updateDailySummary { $0.usage.watchAlertAcknowledgementCount += 1 }
    }

    @MainActor
    func didStartPresetOnWatch() {
        updateDailySummary { $0.usage.watchPresetCount += 1 }
    }

    func didReceiveWatchUsage(_ summary: WatchUsageSummary) {
        logEvent("Watch daily summary", withProperties: summary.properties, outOfSession: true)
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

    @MainActor
    func didAddCarbs(source: String, isFavoriteFood: Bool = false) {
        logEvent("Carb entry created", withProperties: ["source" : source, "isFavoriteFood": isFavoriteFood], outOfSession: source != "Phone")
        updateDailySummary { $0.usage.carbEntryCounts[source, default: 0] += 1 }
    }

    func didRetryBolus() {
        logEvent("Bolus Retry")
    }

    @MainActor
    func didBolus(source: String) {
        logEvent("Bolus set", withProperties: ["source" : source], outOfSession: source != "Phone")
        updateDailySummary { $0.usage.bolusCounts[source, default: 0] += 1 }
    }

    // MARK: - Daily Summary

    @MainActor
    func didStoreGlucose(_ samples: [StoredGlucoseSample]) {
        updateDailySummary { summary in
            for sample in samples where !sample.wasUserEntered {
                summary.glucoseCount += 1
                guard sample.isBackfill else {
                    continue
                }
                summary.backfillCount += 1
                if let receivedDate = sample.receivedDate {
                    summary.maxBackfillAge = max(summary.maxBackfillAge, receivedDate.timeIntervalSince(sample.startDate))
                }
            }
        }
    }

    @MainActor
    func loopDidSucceed(_ duration: TimeInterval) {
        updateDailySummary { summary in
            summary.loopSuccessCount += 1
            summary.totalLoopDuration += duration
            summary.maxLoopDuration = max(summary.maxLoopDuration, duration)
        }
    }

    @MainActor
    func loopDidError(error: LoopError) {
        updateDailySummary { $0.loopErrorCounts[error.issueId, default: 0] += 1 }
    }

    @MainActor
    func identifyState() {
        guard let state = stateProvider?() else {
            return
        }
        identify("Closed Loop", value: state.closedLoop ? "On" : "Off")
        identify("Dosing Strategy", value: state.dosingStrategy)
        identify("Integral Retrospective Correction", value: state.integralRetrospectiveCorrection ? "On" : "Off")
        identify("Glucose Based Partial Application", value: state.glucoseBasedPartialApplication ? "On" : "Off")
        identify("Guard + Runway", value: state.guardAndRunway ? "On" : "Off")
        identify("Slow Retrospective Correction", value: state.slowRetrospectiveCorrection ? "On" : "Off")
        lastState = state
    }

    @MainActor
    private func updateDailySummary(_ update: (inout AnalyticsDailySummary) -> Void, now: Date = Date()) {
        let day = Calendar.current.startOfDay(for: now)
        var summary = UserDefaults.standard.analyticsDailySummary ?? AnalyticsDailySummary(day: day)

        if summary.day != day {
            logEvent("Daily summary", withProperties: summary.properties, outOfSession: true)
            summary = AnalyticsDailySummary(day: day)
        }

        update(&summary)

        if let state = stateProvider?() {
            summary.state = state
            if let lastState, state != lastState {
                logStateChanges(from: lastState, to: state)
                identifyState()
            }
        }

        UserDefaults.standard.analyticsDailySummary = summary
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
        if newState.guardAndRunway != oldState.guardAndRunway {
            logEvent("Algorithm experiment change", withProperties: ["experiment": "Guard + Runway", "enabled": newState.guardAndRunway])
        }
        if newState.slowRetrospectiveCorrection != oldState.slowRetrospectiveCorrection {
            logEvent("Algorithm experiment change", withProperties: ["experiment": "Slow Retrospective Correction", "enabled": newState.slowRetrospectiveCorrection])
        }
    }

    func didDisplayAlert(identifier: String, interruptionLevel: Alert.InterruptionLevel, scheduled: Bool) {
        logEvent("Alert Displayed", withProperties: ["identifier": identifier, "interruptionLevel": interruptionLevel.rawValue, "scheduled": scheduled], outOfSession: scheduled)
    }

    @MainActor
    func didEnactOverride(kind: String, duration: TemporaryScheduleOverride.Duration, activityType: String? = nil) {
        var properties: [String: Any] = ["kind": kind]

        switch duration {
        case .finite(let interval):
            properties["durationMinutes"] = Int(interval.minutes)
        case .indefinite:
            properties["durationMinutes"] = "indefinite"
        }

        properties["activityType"] = activityType

        logEvent("Override Enacted", withProperties: properties)
        updateDailySummary { $0.usage.overrideCounts[kind, default: 0] += 1 }
    }

    func didEndOverride(kind: String) {
        logEvent("Override Ended", withProperties: ["kind": kind])
    }
}


// MARK: - PresetActivationObserver
extension AnalyticsServicesManager: PresetActivationObserver {
    func presetActivated(context: TemporaryScheduleOverride.Context, duration: TemporaryScheduleOverride.Duration) {
        switch context {
        case .activity(let activity):
            didEnactOverride(kind: context.analyticsKind, duration: activity.preset.duration, activityType: activity.activityType.rawValue)
        default:
            didEnactOverride(kind: context.analyticsKind, duration: duration)
        }
    }

    func presetDeactivated(context: TemporaryScheduleOverride.Context) {
        didEndOverride(kind: context.analyticsKind)
    }
}

extension TemporaryScheduleOverride.Context {
    var analyticsKind: String {
        switch self {
        case .preMeal: return "preMeal"
        case .custom: return "custom"
        case .preset: return "preset"
        case .activity: return "activity"
        }
    }
}

struct AnalyticsState: Codable, Equatable {
    var closedLoop: Bool
    var dosingStrategy: String
    var integralRetrospectiveCorrection: Bool
    var glucoseBasedPartialApplication: Bool
    var guardAndRunway: Bool
    var slowRetrospectiveCorrection: Bool

    init(closedLoop: Bool, dosingStrategy: String, integralRetrospectiveCorrection: Bool, glucoseBasedPartialApplication: Bool, guardAndRunway: Bool, slowRetrospectiveCorrection: Bool) {
        self.closedLoop = closedLoop
        self.dosingStrategy = dosingStrategy
        self.integralRetrospectiveCorrection = integralRetrospectiveCorrection
        self.glucoseBasedPartialApplication = glucoseBasedPartialApplication
        self.guardAndRunway = guardAndRunway
        self.slowRetrospectiveCorrection = slowRetrospectiveCorrection
    }

    // Summaries stored before guardAndRunway or slowRetrospectiveCorrection was added lack them
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        closedLoop = try container.decode(Bool.self, forKey: .closedLoop)
        dosingStrategy = try container.decode(String.self, forKey: .dosingStrategy)
        integralRetrospectiveCorrection = try container.decode(Bool.self, forKey: .integralRetrospectiveCorrection)
        glucoseBasedPartialApplication = try container.decode(Bool.self, forKey: .glucoseBasedPartialApplication)
        guardAndRunway = try container.decodeIfPresent(Bool.self, forKey: .guardAndRunway) ?? false
        slowRetrospectiveCorrection = try container.decodeIfPresent(Bool.self, forKey: .slowRetrospectiveCorrection) ?? false
    }
}

struct AnalyticsDailySummary: Codable, Equatable {
    var day: Date
    var utcOffset = TimeZone.current.secondsFromGMT()
    var loopSuccessCount = 0
    var totalLoopDuration: TimeInterval = 0
    var maxLoopDuration: TimeInterval = 0
    var loopErrorCounts: [String: Int] = [:]
    var glucoseCount = 0
    var backfillCount = 0
    var maxBackfillAge: TimeInterval = 0
    var state: AnalyticsState?
    private var storedUsage: AnalyticsUsage?

    init(day: Date) {
        self.day = day
    }

    var usage: AnalyticsUsage {
        get { storedUsage ?? AnalyticsUsage() }
        set { storedUsage = newValue }
    }

    mutating func addForegroundSession(duration: TimeInterval, touchCount: Int) {
        usage.foreground.add(duration: duration)
        usage.touchCount += touchCount
    }

    var properties: [AnyHashable: Any] {
        var properties: [AnyHashable: Any] = [
            "day": ISO8601DateFormatter.string(from: day, timeZone: TimeZone(secondsFromGMT: utcOffset) ?? .current, formatOptions: .withFullDate),
            "utcOffset": utcOffset,
            "loopSuccessCount": loopSuccessCount,
            "meanLoopDuration": loopSuccessCount > 0 ? totalLoopDuration / Double(loopSuccessCount) : 0,
            "maxLoopDuration": maxLoopDuration,
            "loopErrorCount": loopErrorCounts.values.reduce(0, +),
            "loopErrorCounts": loopErrorCounts,
            "glucoseCount": glucoseCount,
            "backfillCount": backfillCount,
            "maxBackfillAgeMinutes": Int(maxBackfillAge.minutes)
        ]
        if let state {
            properties["closedLoop"] = state.closedLoop
            properties["dosingStrategy"] = state.dosingStrategy
            properties["integralRetrospectiveCorrection"] = state.integralRetrospectiveCorrection
            properties["glucoseBasedPartialApplication"] = state.glucoseBasedPartialApplication
            properties["guardAndRunway"] = state.guardAndRunway
            properties["slowRetrospectiveCorrection"] = state.slowRetrospectiveCorrection
        }
        properties.merge(usage.properties) { current, _ in current }
        return properties
    }
}

struct AnalyticsUsage: Codable, Equatable {
    var foreground = ForegroundSessions()
    var touchCount = 0
    var notificationOpenCount = 0
    var linkOpenCount = 0
    var alertAcknowledgementCount = 0
    var screenCounts: [String: Int] = [:]
    var bolusCounts: [String: Int] = [:]
    var carbEntryCounts: [String: Int] = [:]
    var overrideCounts: [String: Int] = [:]
    var watchContextRequestCount = 0
    var watchAlertAcknowledgementCount = 0
    var watchPresetCount = 0

    var properties: [AnyHashable: Any] {
        var properties: [AnyHashable: Any] = [
            "touchCount": touchCount,
            "notificationOpenCount": notificationOpenCount,
            "linkOpenCount": linkOpenCount,
            "alertAcknowledgementCount": alertAcknowledgementCount,
            "screenCounts": screenCounts,
            "bolusCount": bolusCounts.values.reduce(0, +),
            "bolusCounts": bolusCounts,
            "carbEntryCount": carbEntryCounts.values.reduce(0, +),
            "carbEntryCounts": carbEntryCounts,
            "overrideCount": overrideCounts.values.reduce(0, +),
            "overrideCounts": overrideCounts,
            "watchContextRequestCount": watchContextRequestCount,
            "watchAlertAcknowledgementCount": watchAlertAcknowledgementCount,
            "watchPresetCount": watchPresetCount
        ]
        for (key, value) in foreground.properties(prefix: "foreground") {
            properties[key] = value
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

