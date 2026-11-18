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

    func testEnactBolusStoresMetadataForTheDoseIdSentToThePump() async throws {
        let decisionId = UUID()
        pumpManager.enactedDoseIds = []

        try await deviceDataManager.enactBolus(units: 1, metadata: DoseMetadata(origin: .user, device: .watch, decisionId: decisionId), activationType: .manualRecommendationAccepted)

        let doseId = try XCTUnwrap(pumpManager.enactedDoseIds.first)
        let metadata = try await deviceDataManager.doseMetadataStore.metadata(for: doseId)
        XCTAssertEqual(metadata, DoseMetadata(origin: .user, device: .watch, decisionId: decisionId, activationType: .manualRecommendationAccepted))
    }

    func testAutomaticDosesStoreMetadataWithTheDecision() async throws {
        let decisionId = UUID()
        pumpManager.enactedDoseIds = []

        try await deviceDataManager.send(bolus: 0.5, tempBasal: TempBasalRecommendation(unitsPerHour: 1, duration: .minutes(30)), decisionId: decisionId, to: pumpManager)

        XCTAssertEqual(pumpManager.enactedDoseIds.count, 2)
        let metadata = try await deviceDataManager.doseMetadataStore.metadata(for: pumpManager.enactedDoseIds)
        XCTAssertEqual(metadata[pumpManager.enactedDoseIds[0]], DoseMetadata(origin: .automatic, device: .phone, decisionId: decisionId))
        XCTAssertEqual(metadata[pumpManager.enactedDoseIds[1]], DoseMetadata(origin: .automatic, device: .phone, decisionId: decisionId, activationType: .automatic))
    }

    func testValidateMaxTempBasalDoesntCancelTempBasalIfHigher() async throws {
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: Date(),
            value: 3.0,
            unit: .unitsPerHour,
            doseId: nil,
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
            doseId: nil
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

    func testReceivedUnreliableCGMReadingCancelsTempBasal() {
        let dose = DoseEntry(
            type: .tempBasal,
            startDate: Date(),
            value: 5.0,
            unit: .unitsPerHour,
            doseId: nil
        )
        pumpManager.status.basalDeliveryState = .tempBasal(dose)

        settingsManager.mutateLoopSettings { settings in
            settings.basalRateSchedule = BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 3.0)])
        }

        loopControlMock.cancelExpectation = expectation(description: "Temp basal cancel")

        if let deviceManager = self.deviceDataManager {
            Task.detached {
                await deviceManager.cgmManager(self.cgmManager, hasNew: .unreliableData)
            }
        }

        wait(for: [loopControlMock.cancelExpectation!], timeout: 1)

        XCTAssertEqual(loopControlMock.lastCancelActiveTempBasalReason, .unreliableCGMData)
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
