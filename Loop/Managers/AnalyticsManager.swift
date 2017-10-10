//
//  AnalyticsManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 4/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import Amplitude


final class AnalyticsManager: IdentifiableClass {

    var amplitudeService: AmplitudeService {
        didSet {
            try! KeychainManager().setAmplitudeAPIKey(amplitudeService.APIKey)
        }
    }

    init() {
        if let APIKey = KeychainManager().getAmplitudeAPIKey() {
            amplitudeService = AmplitudeService(APIKey: APIKey)
        } else {
            amplitudeService = AmplitudeService(APIKey: nil)
        }

        logger = DiagnosticLogger.shared?.forCategory(type(of: self).className)
    }

    static let shared = AnalyticsManager()

    // MARK: - Helpers

    private var logger: CategoryLogger?

    private func logEvent(_ name: String, withProperties properties: [AnyHashable: Any]? = nil, outOfSession: Bool = false) {
        logger?.debug("\(name) \(properties ?? [:])")
        amplitudeService.client?.logEvent(name, withEventProperties: properties, outOfSession: outOfSession)
    }

    // MARK: - UIApplicationDelegate

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable: Any]?) {
        logEvent("App Launch")
    }

    // MARK: - Screens

    func didDisplayBolusScreen() {
        logEvent("Bolus Screen")
    }

    func didDisplaySettingsScreen() {
        logEvent("Settings Screen")
    }

    func didDisplayStatusScreen() {
        logEvent("Status Screen")
    }

    // MARK: - Config Events

    func didChangeRileyLinkConnectionState() {
        logEvent("RileyLink Connection")
    }

    func transmitterTimeDidDrift(_ drift: TimeInterval) {
        logEvent("Transmitter time change", withProperties: ["value" : drift])
    }

    func pumpBatteryWasReplaced() {
        logEvent("Pump battery replacement")
    }

    func reservoirWasRewound() {
        logEvent("Pump reservoir rewind")
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

    func didChangeGlucoseTargetRangeSchedule() {
        logEvent("Glucose target range change")
    }

    func didChangeLoopSettings(from oldValue: LoopSettings, to newValue: LoopSettings) {
        logEvent("Loop settings change")

        if newValue.maximumBasalRatePerHour != oldValue.maximumBasalRatePerHour {
            logEvent("Maximum basal rate change")
        }

        if newValue.maximumBolus != oldValue.maximumBolus {
            logEvent("Maximum bolus change")
        }

        if newValue.suspendThreshold != oldValue.suspendThreshold {
            logEvent("Minimum BG Guard change")
        }
    }

    // MARK: - Loop Events

    func didAddCarbsFromWatch(_ carbs: Double) {
        logEvent("Carb entry created", withProperties: ["source" : "Watch"], outOfSession: true)
    }

    func didRetryBolus() {
        logEvent("Bolus Retry", outOfSession: true)
    }

    func didSetBolusFromWatch(_ units: Double) {
        logEvent("Bolus set", withProperties: ["source" : "Watch"], outOfSession: true)
    }

    func loopDidSucceed() {
        logEvent("Loop success", outOfSession: true)
    }

    func loopDidError() {
        logEvent("Loop error", outOfSession: true)
    }
}
