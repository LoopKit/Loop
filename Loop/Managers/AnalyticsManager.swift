//
//  AnalyticsManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 4/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import AmplitudeFramework


class AnalyticsManager {

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
    }

    static let sharedManager = AnalyticsManager()

    // MARK: - Helpers

    private var isSimulator: Bool = TARGET_OS_SIMULATOR != 0

    private func logEvent(name: String, withProperties properties: [NSObject: AnyObject]? = nil, outOfSession: Bool = false) {
        if isSimulator {
            NSLog("\(name) \(properties ?? [:])")
        } else {
            amplitudeService.client?.logEvent(name, withEventProperties: properties, outOfSession: outOfSession)
        }

    }

    // MARK: - UIApplicationDelegate

    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) {
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

    func transmitterTimeDidDrift(drift: NSTimeInterval) {
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

    func didChangeInsulinActionDuration() {
        logEvent("Insulin action duration change")
    }

    func didChangeInsulinSensitivitySchedule() {
        logEvent("Insulin sensitivity change")
    }

    func didChangeGlucoseTargetRangeSchedule() {
        logEvent("Glucose target range change")
    }

    func didChangeMaximumBasalRate() {
        logEvent("Maximum basal rate change")
    }

    func didChangeMaximumBolus() {
        logEvent("Maximum bolus change")
    }

    // MARK: - Loop Events

    func didAddCarbsFromWatch(carbs: Double) {
        logEvent("Carb entry created", withProperties: ["source" : "Watch", "value": carbs], outOfSession: true)
    }

    func didRetryBolus() {
        logEvent("Bolus Retry", outOfSession: true)
    }

    func didSetBolusFromWatch(units: Double) {
        logEvent("Bolus set", withProperties: ["source" : "Watch", "value": units], outOfSession: true)
    }

    func loopDidSucceed() {
        logEvent("Loop success", outOfSession: true)
    }

    func loopDidError() {
        logEvent("Loop error", outOfSession: true)
    }
}