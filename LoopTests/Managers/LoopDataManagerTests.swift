//
//  LoopDataManagerTests.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/4/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
@testable import LoopCore
@testable import Loop

public typealias JSONDictionary = [String: Any]

enum DosingTestScenario {
    case flatAndStable
    case highAndStable
    case highAndRisingWithCOB
    case lowAndFallingWithCOB
    case lowWithLowTreatment
    case highAndFalling
}

extension TimeZone {
    static var fixtureTimeZone: TimeZone {
        return TimeZone(secondsFromGMT: 25200)!
    }
    
    static var utcTimeZone: TimeZone {
        return TimeZone(secondsFromGMT: 0)!
    }
}

extension ISO8601DateFormatter {
    static func localTimeDate(timeZone: TimeZone = .fixtureTimeZone) -> Self {
        let formatter = self.init()

        formatter.formatOptions = .withInternetDateTime
        formatter.formatOptions.subtract(.withTimeZone)
        formatter.timeZone = timeZone

        return formatter
    }
}

class LoopDataManagerTests: XCTestCase {
    // MARK: Constants for testing
    let retrospectiveCorrectionEffectDuration = TimeInterval(hours: 1)
    let retrospectiveCorrectionGroupingInterval = 1.01
    let retrospectiveCorrectionGroupingIntervalMultiplier = 1.01
    let inputDataRecencyInterval = TimeInterval(minutes: 15)
    let dateFormatter = ISO8601DateFormatter.localTimeDate()
    let defaultAccuracy = 1.0 / 40.0
    
    var suspendThreshold: GlucoseThreshold {
        return GlucoseThreshold(unit: HKUnit.milligramsPerDeciliter, value: 75)
    }
    
    var adultExponentialInsulinModel: InsulinModel = ExponentialInsulinModel(actionDuration: 21600.0, peakActivityTime: 4500.0)

    var glucoseTargetRangeSchedule: GlucoseRangeSchedule {
        return GlucoseRangeSchedule(unit: HKUnit.milligramsPerDeciliter, dailyItems: [
            RepeatingScheduleValue(startTime: TimeInterval(0), value: DoubleRange(minValue: 100, maxValue: 110)),
            RepeatingScheduleValue(startTime: TimeInterval(28800), value: DoubleRange(minValue: 90, maxValue: 100)),
            RepeatingScheduleValue(startTime: TimeInterval(75600), value: DoubleRange(minValue: 100, maxValue: 110))
        ], timeZone: .utcTimeZone)!
    }
    
    // MARK: Mock stores
    var now: Date!
    var dosingDecisionStore: MockDosingDecisionStore!
    var automaticDosingStatus: AutomaticDosingStatus!
    var loopDataManager: LoopDataManager!
    
    func setUp(for test: DosingTestScenario,
               basalDeliveryState: PumpManagerStatus.BasalDeliveryState? = nil,
               maxBolus: Double = 10,
               maxBasalRate: Double = 5.0,
               dosingStrategy: AutomaticDosingStrategy = .tempBasalOnly)
    {
        let basalRateSchedule = loadBasalRateScheduleFixture("basal_profile")
        let carbRatioSchedule = CarbRatioSchedule(
            unit: .gram(),
            dailyItems: [
                RepeatingScheduleValue(startTime: 0.0, value: 10.0),
            ],
            timeZone: .utcTimeZone
        )!

        let settings = LoopSettings(
            dosingEnabled: false,
            glucoseTargetRangeSchedule: glucoseTargetRangeSchedule,
            basalRateSchedule: basalRateSchedule,
            carbRatioSchedule: carbRatioSchedule,
            maximumBasalRatePerHour: maxBasalRate,
            maximumBolus: maxBolus,
            suspendThreshold: suspendThreshold,
            automaticDosingStrategy: dosingStrategy
        )
        
        let doseStore = MockDoseStore(for: test)
        doseStore.basalProfile = basalRateSchedule
        doseStore.basalProfileApplyingOverrideHistory = doseStore.basalProfile
        let glucoseStore = MockGlucoseStore(for: test)
        let carbStore = MockCarbStore(for: test)
        
        let currentDate = glucoseStore.latestGlucose!.startDate
        now = currentDate
        
        dosingDecisionStore = MockDosingDecisionStore()
        automaticDosingStatus = AutomaticDosingStatus(automaticDosingEnabled: true, isAutomaticDosingAllowed: true)
        loopDataManager = LoopDataManager(
            lastLoopCompleted: currentDate,
            basalDeliveryState: basalDeliveryState ?? .active(currentDate),
            settings: settings,
            overrideHistory: TemporaryScheduleOverrideHistory(),
            analyticsServicesManager: AnalyticsServicesManager(),
            localCacheDuration: .days(1),
            doseStore: doseStore,
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            dosingDecisionStore: dosingDecisionStore,
            latestStoredSettingsProvider: MockLatestStoredSettingsProvider(),
            now: { currentDate },
            pumpInsulinType: .novolog,
            automaticDosingStatus: automaticDosingStatus,
            trustedTimeOffset: { 0 }
        )
    }
    
    override func tearDownWithError() throws {
        loopDataManager = nil
    }
}

extension LoopDataManagerTests {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }
    
    func loadBasalRateScheduleFixture(_ resourceName: String) -> BasalRateSchedule {
        let fixture: [JSONDictionary] = loadFixture(resourceName)

        let items = fixture.map {
            return RepeatingScheduleValue(startTime: TimeInterval(minutes: $0["minutes"] as! Double), value: $0["rate"] as! Double)
        }

        return BasalRateSchedule(dailyItems: items, timeZone: .utcTimeZone)!
    }
}
