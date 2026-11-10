//
//  DeviceDataManagerTests.swift
//  LoopTests
//
//  Created by Pete Schwamb on 10/31/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import HealthKit
import LoopKit
import LoopKitUI
import LoopCore
@testable import Loop

@MainActor
final class DeviceDataManagerTests: XCTestCase {

    var deviceDataManager: DeviceDataManager!
    let mockDecisionStore = MockDosingDecisionStore()
    let pumpManager: MockPumpManager = MockPumpManager()
    let cgmManager: MockCGMManager = MockCGMManager()
    let trustedTimeChecker = MockTrustedTimeChecker()
    let loopControlMock = LoopControlMock()
    var settingsManager: SettingsManager!
    var uploadEventListener: MockUploadEventListener!


    class MockAlertIssuer: AlertIssuer {
        func issueAlert(_ alert: LoopKit.Alert) {
        }

        func retractAlert(identifier: LoopKit.Alert.Identifier) {
        }
    }

    override func setUp() async throws {
        let mockUserNotificationCenter = MockUserNotificationCenter()
        let mockBluetoothProvider = MockBluetoothProvider()
        let alertPresenter = MockPresenter()

        let alertManager = AlertManager(
            alertPresenter: alertPresenter,
            userNotificationAlertScheduler: MockUserNotificationAlertScheduler(userNotificationCenter: mockUserNotificationCenter),
            bluetoothProvider: mockBluetoothProvider,
            analyticsServicesManager: AnalyticsServicesManager()
        )

        let persistenceController = PersistenceController.mock()

        let healthStore = HKHealthStore()

        let carbStore = CarbStore(
            cacheStore: persistenceController,
            cacheLength: .days(1)
        )

        let doseStore = await DoseStore(
            cacheStore: persistenceController
        )

        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let deviceLogDirectory = documentsDirectory.appendingPathComponent("DeviceLog")
        if !fileManager.fileExists(atPath: deviceLogDirectory.path) {
            do {
                try fileManager.createDirectory(at: deviceLogDirectory, withIntermediateDirectories: false)
            } catch let error {
                preconditionFailure("Could not create DeviceLog directory: \(error)")
            }
        }
        let deviceLog = PersistentDeviceLog(storageFile: deviceLogDirectory.appendingPathComponent("Storage.sqlite"))

        let glucoseStore = await GlucoseStore(cacheStore: persistenceController)

        let cgmEventStore = CgmEventStore(cacheStore: persistenceController)

        self.settingsManager = SettingsManager(cacheStore: persistenceController, expireAfter: .days(1), alertMuter: AlertMuter())

        self.uploadEventListener = MockUploadEventListener()

        deviceDataManager = DeviceDataManager(
            pluginManager: PluginManager(),
            deviceLog: deviceLog,
            alertManager: alertManager,
            settingsManager: settingsManager,
            healthStore: healthStore,
            carbStore: carbStore,
            doseStore: doseStore,
            glucoseStore: glucoseStore,
            cgmEventStore: cgmEventStore,
            uploadEventListener: uploadEventListener,
            crashRecoveryManager: CrashRecoveryManager(alertIssuer: MockAlertIssuer()),
            loopControl: loopControlMock,
            analyticsServicesManager: AnalyticsServicesManager(),
            activeServicesProvider: self,
            activeStatefulPluginsProvider: self,
            bluetoothProvider: mockBluetoothProvider,
            alertPresenter: alertPresenter,
            cacheStore: persistenceController,
            localCacheDuration: .days(1),
            displayGlucosePreference: DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter),
            displayGlucoseUnitBroadcaster: self
        )

        deviceDataManager.pumpManager = pumpManager
        deviceDataManager.cgmManager = cgmManager
    }

    func testValidateMaxTempBasalDoesntCancelTempBasalIfHigher() async throws {
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: Date(),
            value: 3.0,
            unit: .unitsPerHour,
            decisionId: nil,
            automatic: true
        )
        pumpManager.status.basalDeliveryState = .tempBasal(dose)

        let newLimits = DeliveryLimits(
            maximumBasalRate: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: 5),
            maximumBolus: nil
        )
        let limits = try await deviceDataManager.syncDeliveryLimits(deliveryLimits: newLimits)

        XCTAssertNil(loopControlMock.lastCancelActiveTempBasalReason)
        XCTAssertTrue(mockDecisionStore.dosingDecisions.isEmpty)
        XCTAssertEqual(limits.maximumBasalRate, newLimits.maximumBasalRate)
    }

    func testValidateMaxTempBasalCancelsTempBasalIfLower() async throws {
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: Date(),
            endDate: nil,
            value: 5.0,
            unit: .unitsPerHour,
            decisionId: nil
        )
        pumpManager.status.basalDeliveryState = .tempBasal(dose)

        let newLimits = DeliveryLimits(
            maximumBasalRate: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: 3),
            maximumBolus: nil
        )
        let limits = try await deviceDataManager.syncDeliveryLimits(deliveryLimits: newLimits)

        XCTAssertEqual(.maximumBasalRateChanged, loopControlMock.lastCancelActiveTempBasalReason)
        XCTAssertEqual(limits.maximumBasalRate, newLimits.maximumBasalRate)
    }

    func testAPumpErrorIsThrownForCallersThatReportTheOutcome() async {
        pumpManager.enactBolusError = .communication(nil)
        do {
            try await deviceDataManager.enactBolus(units: 1, decisionId: nil, activationType: .manualNoRecommendation, throwingPumpErrors: true)
            XCTFail("A failed bolus must not be reported as delivered")
        } catch PumpManagerError.communication {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testAnUncertainDeliveryIsThrownForCallersThatReportTheOutcome() async {
        pumpManager.enactBolusError = .uncertainDelivery
        do {
            try await deviceDataManager.enactBolus(units: 1, decisionId: nil, activationType: .manualNoRecommendation, throwingPumpErrors: true)
            XCTFail("An uncertain bolus must not be reported as delivered")
        } catch PumpManagerError.uncertainDelivery {
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testPumpErrorsAreNotThrownByDefault() async throws {
        pumpManager.enactBolusError = .communication(nil)
        try await deviceDataManager.enactBolus(units: 1, decisionId: nil, activationType: .manualNoRecommendation)
        pumpManager.enactBolusError = .uncertainDelivery
        try await deviceDataManager.enactBolus(units: 1, decisionId: nil, activationType: .manualNoRecommendation)
    }

    func testReceivedUnreliableCGMReadingCancelsTempBasal() {
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: Date(),
            value: 5.0,
            unit: .unitsPerHour,
            decisionId: nil
        )
        pumpManager.status.basalDeliveryState = .tempBasal(dose)

        settingsManager.mutateLoopSettings { settings in
            settings.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 3.0)])
        }

        loopControlMock.cancelExpectation = expectation(description: "Temp basal cancel")

        if let deviceManager = self.deviceDataManager {
            cgmManager.delegateQueue.async {
                deviceManager.cgmManager(self.cgmManager, hasNew: .unreliableData)
            }
        }

        wait(for: [loopControlMock.cancelExpectation!], timeout: 1)

        XCTAssertEqual(loopControlMock.lastCancelActiveTempBasalReason, .unreliableCGMData)
    }

    private func manualTempBasal(automatic: Bool?, endDate: Date) -> DoseEntry {
        DoseEntry(type: .tempBasal, startDate: Date().addingTimeInterval(-.minutes(10)), endDate: endDate, value: 2.0, unit: .unitsPerHour, decisionId: nil, automatic: automatic)
    }

    /// What the watch plugin's loop state reports as closed loop (the host forwards
    /// `isAutomaticDosingActive`): closed with Closed Loop on and no manual temp
    /// basal, open during a manual temp basal, as Loop's loop icon shows it.
    func testAutomaticDosingIsActiveOnlyWithClosedLoopOnAndNoManualTempBasal() {
        settingsManager.dosingEnabled = true
        pumpManager.status.basalDeliveryState = .active(Date())
        XCTAssertTrue(deviceDataManager.isAutomaticDosingActive)

        pumpManager.status.basalDeliveryState = .tempBasal(manualTempBasal(automatic: true, endDate: Date().addingTimeInterval(.minutes(20))))
        XCTAssertTrue(deviceDataManager.isAutomaticDosingActive)

        pumpManager.status.basalDeliveryState = .tempBasal(manualTempBasal(automatic: false, endDate: Date().addingTimeInterval(.minutes(20))))
        XCTAssertFalse(deviceDataManager.isAutomaticDosingActive)

        // A manual temp basal that has ended no longer holds the loop open.
        pumpManager.status.basalDeliveryState = .tempBasal(manualTempBasal(automatic: false, endDate: Date().addingTimeInterval(-.minutes(1))))
        XCTAssertTrue(deviceDataManager.isAutomaticDosingActive)

        settingsManager.dosingEnabled = false
        pumpManager.status.basalDeliveryState = .active(Date())
        XCTAssertFalse(deviceDataManager.isAutomaticDosingActive)
    }

    /// The watch host signals a loop change when this flips: off for a manual temp
    /// basal, back on when it ends.
    func testPumpIsAllowingAutomationFollowsAManualTempBasal() {
        var status = pumpManager.status
        status.basalDeliveryState = .tempBasal(manualTempBasal(automatic: false, endDate: Date().addingTimeInterval(.minutes(20))))
        deviceDataManager.updatePumpIsAllowingAutomation(status: status)
        XCTAssertFalse(deviceDataManager.pumpIsAllowingAutomation)

        status.basalDeliveryState = .active(Date())
        deviceDataManager.updatePumpIsAllowingAutomation(status: status)
        XCTAssertTrue(deviceDataManager.pumpIsAllowingAutomation)
    }

    func testUploadEventListener() {
        let alertStore = AlertStore()
        deviceDataManager.alertStoreHasUpdatedAlertData(alertStore)
        XCTAssertEqual(uploadEventListener.lastUploadTriggeringType, .alert)
    }

}

extension DeviceDataManagerTests: ActiveServicesProvider {
    nonisolated var activeServices: [LoopKit.Service] {
        return []
    }
    

}

extension DeviceDataManagerTests: ActiveStatefulPluginsProvider {
    nonisolated var activeStatefulPlugins: [LoopKit.StatefulPluggable] {
        return []
    }
}

extension DeviceDataManagerTests: DisplayGlucoseUnitBroadcaster {
    func addDisplayGlucoseUnitObserver(_ observer: LoopKitUI.DisplayGlucoseUnitObserver) {
    }
    
    func removeDisplayGlucoseUnitObserver(_ observer: LoopKitUI.DisplayGlucoseUnitObserver) {
    }
    
    func notifyObserversOfDisplayGlucoseUnitChange(to displayGlucoseUnit: LoopUnit) {
    }
}
