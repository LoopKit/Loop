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

    // MARK: - Helpers

    private static var isSimulator: Bool = TARGET_OS_SIMULATOR != 0

    private static var amplitudeAPIKey: String? {
        if let settings = NSBundle.mainBundle().remoteSettings {
            return settings["AmplitudeAPIKey"]
        }

        return nil
    }

    private static func logEvent(name: String, withProperties properties: [NSObject: AnyObject]? = nil, outOfSession: Bool = false) {
        guard amplitudeAPIKey != nil else {
            return
        }

        if isSimulator {
            NSLog("\(name) \(properties ?? [:])")
        } else {
            Amplitude.instance().logEvent(name, withEventProperties: properties, outOfSession: outOfSession)
        }

    }

    // MARK: - UIApplicationDelegate

    static func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) {

        if let APIKey = amplitudeAPIKey {
            Amplitude.instance().initializeApiKey(APIKey)
        }
    }

    // MARK: - Screens

    static func didDisplayBolusScreen() {
        logEvent("Bolus Screen")
    }

    static func didDisplaySettingsScreen() {
        logEvent("Settings Screen")
    }

    static func didDisplayStatusScreen() {
        logEvent("Status Screen")
    }

    // MARK: - Config Events

    static func didChangeRileyLinkConnectionState() {
        logEvent("RileyLink Connection")
    }

    static func transmitterTimeDidDrift(drift: NSTimeInterval) {
        logEvent("Transmitter time change", withProperties: ["value" : drift])
    }

    static func didChangeBasalRateSchedule() {
        logEvent("Basal rate change")
    }

    static func didChangeCarbRatioSchedule() {
        logEvent("Carb ratio change")
    }

    static func didChangeInsulinActionDuration() {
        logEvent("Insulin action duration change")
    }

    static func didChangeInsulinSensitivitySchedule() {
        logEvent("Insulin sensitivity change")
    }

    static func didChangeGlucoseTargetRangeSchedule() {
        logEvent("Glucose target range change")
    }

    static func didChangeMaximumBasalRate() {
        logEvent("Maximum basal rate change")
    }

    static func didChangeMaximumBolus() {
        logEvent("Maximum bolus change")
    }

    // MARK: - Loop Events

    static func didAddCarbsFromWatch(carbs: Double) {
        logEvent("Carb entry created", withProperties: ["source" : "Watch", "value": carbs], outOfSession: true)
    }

    static func didRetryBolus() {
        logEvent("Bolus Retry", outOfSession: true)
    }

    static func didSetBolusFromWatch(units: Double) {
        logEvent("Bolus set", withProperties: ["source" : "Watch", "value": units], outOfSession: true)
    }

    static func loopDidSucceed() {
        logEvent("Loop success", outOfSession: true)
    }

    static func loopDidError() {
        logEvent("Loop error", outOfSession: true)
    }
}