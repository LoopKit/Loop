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

    init() {}

    func addService(_ analyticsService: AnalyticsService) {
        analyticsServices.append(analyticsService)
    }

    func restoreService(_ analyticsService: AnalyticsService) {
        analyticsServices.append(analyticsService)
    }

    func removeService(_ analyticsService: AnalyticsService) {
        analyticsServices.removeAll { $0.serviceIdentifier == analyticsService.serviceIdentifier }
    }

    private func logEvent(_ name: String, withProperties properties: [AnyHashable: Any]? = nil, outOfSession: Bool = false) {
        log.debug("%{public}@ %{public}@", name, String(describing: properties))
        analyticsServices.forEach { $0.recordAnalyticsEvent(name, withProperties: properties, outOfSession: outOfSession) }
    }

    private func identify(_ property: String, value: String) {
        log.debug("Identify %{public}@: %{public}@", property, value)
        analyticsServices.forEach { $0.recordIdentify(property, value: value) }
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

        if newValue.dosingEnabled != oldValue.dosingEnabled {
            logEvent("Closed loop enabled change")
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
    }

    func pumpWasAdded(identifier: String) {
        logEvent("Pump Added", withProperties: ["identifier" : identifier])
    }

    func cgmWasRemoved() {
        logEvent("CGM Removed")
    }

    func cgmWasAdded(identifier: String) {
        logEvent("CGM Added", withProperties: ["identifier" : identifier])
    }


    func didAddCarbs(source: String, amount: Double, inSession: Bool = false) {
        logEvent("Carb entry created", withProperties: ["source" : source, "amount": "\(amount)"], outOfSession: inSession)
    }

    func didRetryBolus() {
        logEvent("Bolus Retry")
    }

    func didBolus(source: String, units: Double, inSession: Bool = false) {
        logEvent("Bolus set", withProperties: ["source" : source, "units": "\(units)"], outOfSession: true)
    }

    func didFetchNewCGMData() {
        logEvent("CGM Fetch", outOfSession: true)
    }

    func loopDidSucceed(_ duration: TimeInterval) {
        logEvent("Loop success", withProperties: ["duration": duration], outOfSession: true)
    }

    func loopDidError(error: LoopError) {
        var props = [AnyHashable: Any]()

        props["issueId"] = error.issueId

        for (detailKey, detail) in error.issueDetails {
            props[detailKey] = detail
        }

        logEvent("Loop error", withProperties: props, outOfSession: true)
    }

    func didIssueAlert(identifier: String, interruptionLevel: Alert.InterruptionLevel) {
        logEvent("Alert Issued", withProperties: ["identifier": identifier, "interruptionLevel": interruptionLevel.rawValue])
    }

    func didEnactOverride(name: String, symbol: String, duration: TemporaryScheduleOverride.Duration) {
        let combinedName = "\(symbol) - \(name)"
        logEvent("Override Enacted", withProperties: ["name": name, "symbol": symbol, "nameWithEmoji": combinedName])
    }

    func didCancelOverride(name: String) {
        logEvent("Override Canceled", withProperties: ["name": name])
    }
}


// MARK: - PresetActivationObserver
extension AnalyticsServicesManager: PresetActivationObserver {
    func presetActivated(context: TemporaryScheduleOverride.Context, duration: TemporaryScheduleOverride.Duration) {
        switch context {
        case .legacyWorkout:
            didEnactOverride(name: "workout", symbol: "", duration: duration)
        case .preMeal:
            didEnactOverride(name: "preMeal", symbol: "", duration: duration)
        case .custom:
            didEnactOverride(name: "custom", symbol: "", duration: duration)
        case .preset(let preset):
            didEnactOverride(name: preset.name, symbol: preset.symbol, duration: duration)
        }
    }

    func presetDeactivated(context: TemporaryScheduleOverride.Context) {
        switch context {
        case .legacyWorkout:
            break
        default:
            break
        }
    }
}

