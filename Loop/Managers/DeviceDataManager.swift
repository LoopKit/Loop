//
//  DeviceDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import LoopCore
import LoopTestingKit
import UserNotifications

final class DeviceDataManager {

    private let queue = DispatchQueue(label: "com.loopkit.DeviceManagerQueue", qos: .utility)

    var pumpManager: PumpManagerUI? {
        
        didSet {
            
            // If the current CGMManager is a PumpManager, we clear it out.
            if cgmManager is PumpManagerUI {
                cgmManager = nil
            }

            pumpManagerHUDProvider = pumpManager?.hudProvider()

            setupPump()
            
            NotificationCenter.default.post(name: .PumpManagerChanged, object: self, userInfo: nil)

            UserDefaults.appGroup?.pumpManager = pumpManager
        }
    }
    
    var pumpManagerHUDProvider: HUDProvider?

    let logger = DiagnosticLogger.shared

    private let log = DiagnosticLogger.shared.forCategory("DeviceManager")

    /// Remember the launch date of the app for diagnostic reporting
    private let launchDate = Date()

    /// Manages authentication for remote services
    let remoteDataManager = RemoteDataManager()

    private var nightscoutDataManager: NightscoutDataManager!

    var lastError: (date: Date, error: Error)? {
        return lockedLastError.value
    }
    private func setLastError(error: Error) {
        lockedLastError.value = (date: Date(), error: error)
    }
    private let lockedLastError: Locked<(date: Date, error: Error)?> = Locked(nil)

    // MARK: - CGM

    var cgmManager: CGMManager? {
        didSet {
            setupCGM()

            UserDefaults.appGroup?.cgmManager = cgmManager
        }
    }

    private var lastBLEDrivenUpdate = Date.distantPast

    private let lockedPumpManagerStatus: Locked<PumpManagerStatus?> = Locked(nil)

    static let batteryReplacementDetectionThreshold = 0.5
    
    var pumpManagerStatus: PumpManagerStatus? {
        get {
            return lockedPumpManagerStatus.value
        }
        set {
            let oldValue = lockedPumpManagerStatus.value
            lockedPumpManagerStatus.value = newValue

            if let status = newValue {
                
                loopManager.doseStore.device = status.device
                
                if let newBatteryValue = status.pumpBatteryChargeRemaining {
                    if newBatteryValue == 0 {
                        NotificationManager.sendPumpBatteryLowNotification()
                    } else {
                        NotificationManager.clearPumpBatteryLowNotification()
                    }
                    
                    if let oldBatteryValue = oldValue?.pumpBatteryChargeRemaining, newBatteryValue - oldBatteryValue >= DeviceDataManager.batteryReplacementDetectionThreshold {
                        AnalyticsManager.shared.pumpBatteryWasReplaced()
                    }
                }
                    
                // Update the pump-schedule based settings
                loopManager.setScheduleTimeZone(status.timeZone)

            } else {
                loopManager.doseStore.device = nil
            }
        }
    }

    /// TODO: Isolate to queue
    private func setupCGM() {
        cgmManager?.cgmManagerDelegate = self
        loopManager.glucoseStore.managedDataInterval = cgmManager?.managedDataInterval

        pumpManager?.updateBLEHeartbeatPreference()
    }

    private func setupPump() {
        pumpManager?.pumpManagerDelegate = self
        
        if let pumpManager = pumpManager {
            self.pumpManagerStatus = pumpManager.status
            self.loopManager.doseStore.device = self.pumpManagerStatus?.device
            self.pumpManagerHUDProvider = pumpManager.hudProvider()
        }

        // Proliferate PumpModel preferences to DoseStore
        if let pumpRecordsBasalProfileStartEvents = pumpManager?.pumpRecordsBasalProfileStartEvents {
            loopManager?.doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
        }
    }

    // MARK: - Configuration

    // MARK: - WatchKit

    fileprivate var watchManager: WatchDataManager!

    // MARK: - Status Extension

    fileprivate var statusExtensionManager: StatusExtensionDataManager!

    // MARK: - Initialization

    private(set) var loopManager: LoopDataManager!

    init() {
        pumpManager = UserDefaults.appGroup?.pumpManager as? PumpManagerUI

        if let cgmManager = UserDefaults.appGroup?.cgmManager {
            self.cgmManager = cgmManager
        } else if UserDefaults.appGroup?.isCGMManagerValidPumpManager == true {
            self.cgmManager = pumpManager as? CGMManager
        }
        
        remoteDataManager.delegate = self
        statusExtensionManager = StatusExtensionDataManager(deviceDataManager: self)
        loopManager = LoopDataManager(
            lastLoopCompleted: statusExtensionManager.context?.lastLoopCompleted,
            lastTempBasal: statusExtensionManager.context?.netBasal?.tempBasal
        )
        watchManager = WatchDataManager(deviceManager: self)
        nightscoutDataManager = NightscoutDataManager(deviceDataManager: self)

        loopManager.delegate = self
        loopManager.carbStore.syncDelegate = remoteDataManager.nightscoutService.uploader
        loopManager.doseStore.delegate = self

        setupPump()
        setupCGM()
    }
}

// MARK: - RemoteDataManagerDelegate
extension DeviceDataManager: RemoteDataManagerDelegate {
    func remoteDataManagerDidUpdateServices(_ dataManager: RemoteDataManager) {
        loopManager.carbStore.syncDelegate = dataManager.nightscoutService.uploader
    }
}

// MARK: - DeviceManagerDelegate
extension DeviceDataManager: DeviceManagerDelegate {
    func scheduleNotification(for manager: DeviceManager,
                              identifier: String,
                              content: UNNotificationContent,
                              trigger: UNNotificationTrigger?) {
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        DispatchQueue.main.async {
            UNUserNotificationCenter.current().add(request)
        }
    }

    func clearNotification(for manager: DeviceManager, identifier: String) {
        DispatchQueue.main.async {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }
}

// MARK: - CGMManagerDelegate
extension DeviceDataManager: CGMManagerDelegate {
    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        self.cgmManager = nil
    }

    func cgmManager(_ manager: CGMManager, didUpdateWith result: CGMResult) {
        /// TODO: Isolate to queue
        switch result {
        case .newData(let values):
            log.default("CGMManager:\(type(of: manager)) did update with new data")

            loopManager.addGlucose(values) { result in
                if manager.shouldSyncToRemoteService {
                    switch result {
                    case .success(let values):
                        self.nightscoutDataManager.uploadGlucose(values, sensorState: manager.sensorState)
                    case .failure:
                        break
                    }
                }

                self.pumpManager?.assertCurrentPumpData()
            }
        case .noData:
            log.default("CGMManager:\(type(of: manager)) did update with no data")

            pumpManager?.assertCurrentPumpData()
        case .error(let error):
            log.default("CGMManager:\(type(of: manager)) did update with error: \(error)")

            self.setLastError(error: error)
            pumpManager?.assertCurrentPumpData()
        }

        pumpManager?.updateBLEHeartbeatPreference()
    }

    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        return loopManager.glucoseStore.latestGlucose?.startDate
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        UserDefaults.appGroup?.cgmManager = manager
    }
}


// MARK: - PumpManagerDelegate
extension DeviceDataManager: PumpManagerDelegate {
    
    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        log.default("PumpManager:\(type(of: pumpManager)) did adjust pump block by \(adjustment)s")

        AnalyticsManager.shared.pumpTimeDidDrift(adjustment)
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        log.default("PumpManager:\(type(of: pumpManager)) did update state")

        UserDefaults.appGroup?.pumpManager = pumpManager
    }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
        log.default("PumpManager:\(type(of: pumpManager)) did fire BLE heartbeat")

        let bleHeartbeatUpdateInterval = TimeInterval(minutes: 4.5)
        guard lastBLEDrivenUpdate.timeIntervalSinceNow < -bleHeartbeatUpdateInterval else {
            log.default("Skipping ble heartbeat")
            return
        }
        lastBLEDrivenUpdate = Date()

        cgmManager?.fetchNewDataIfNeeded { (result) in
            if case .newData = result {
                AnalyticsManager.shared.didFetchNewCGMData()
            }

            if let manager = self.cgmManager {
                // TODO: Isolate to queue?
                self.cgmManager(manager, didUpdateWith: result)
            }
        }
    }

    func pumpManagerShouldProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool {
        return !(cgmManager?.providesBLEHeartbeat == true)
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus) {
        log.default("PumpManager:\(type(of: pumpManager)) did update status: \(status)")
        self.pumpManagerStatus = status
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        log.default("PumpManager:\(type(of: pumpManager)) will deactivate")

        loopManager.doseStore.resetPumpData()
        self.pumpManager = nil
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
        log.default("PumpManager:\(type(of: pumpManager)) did update pumpRecordsBasalProfileStartEvents to \(pumpRecordsBasalProfileStartEvents)")

        loopManager.doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
    }

    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {
        log.error("PumpManager:\(type(of: pumpManager)) did error: \(error)")

        setLastError(error: error)
        nightscoutDataManager.uploadLoopStatus(loopError: error)
    }

    func pumpManager(_ pumpManager: PumpManager, didReadPumpEvents events: [NewPumpEvent], completion: @escaping (_ error: Error?) -> Void) {
        log.default("PumpManager:\(type(of: pumpManager)) did read pump events")

        loopManager.addPumpEvents(events) { (error) in
            if let error = error {
                self.log.error("Failed to addPumpEvents to DoseStore: \(error)")
            }

            completion(error)
        }
    }

    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (_ result: PumpManagerResult<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool)>) -> Void) {
        log.default("PumpManager:\(type(of: pumpManager)) did read reservoir value")

        loopManager.addReservoirValue(units, at: date) { (result) in
            switch result {
            case .failure(let error):
                self.log.error("Failed to addReservoirValue: \(error)")
                completion(.failure(error))
            case .success(let (newValue, lastValue, areStoredValuesContinuous)):
                completion(.success((newValue: newValue, lastValue: lastValue, areStoredValuesContinuous: areStoredValuesContinuous)))

                // Send notifications for low reservoir if necessary
                if let previousVolume = lastValue?.unitVolume {
                    guard newValue.unitVolume > 0 else {
                        NotificationManager.sendPumpReservoirEmptyNotification()
                        return
                    }

                    let warningThresholds: [Double] = [10, 20, 30]

                    for threshold in warningThresholds {
                        if newValue.unitVolume <= threshold && previousVolume > threshold {
                            NotificationManager.sendPumpReservoirLowNotificationForAmount(newValue.unitVolume, andTimeRemaining: nil)
                            break
                        }
                    }

                    if newValue.unitVolume > previousVolume + 1 {
                        AnalyticsManager.shared.reservoirWasRewound()

                        NotificationManager.clearPumpReservoirNotification()
                    }
                }
            }
        }
    }
    
    func pumpManagerRecommendsLoop(_ pumpManager: PumpManager) {
        log.default("PumpManager:\(type(of: pumpManager)) recommends loop")
        loopManager.loop()
    }

    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        return loopManager.doseStore.pumpEventQueryAfterDate
    }

    func startDateToFilterNewReservoirEvents(for manager: PumpManager) -> Date {
        return loopManager.doseStore.lastReservoirValue?.startDate ?? .distantPast
    }
    
}

// MARK: - DoseStoreDelegate
extension DeviceDataManager: DoseStoreDelegate {
    func doseStore(_ doseStore: DoseStore,
        hasEventsNeedingUpload pumpEvents: [PersistedPumpEvent],
        completion completionHandler: @escaping (_ uploadedObjectIDURLs: [URL]) -> Void
    ) {
        /// TODO: Isolate to queue
        guard let uploader = remoteDataManager.nightscoutService.uploader else {
            completionHandler(pumpEvents.map({ $0.objectIDURL }))
            return
        }

        uploader.upload(pumpEvents, fromSource: "loop://\(UIDevice.current.name)") { (result) in
            switch result {
            case .success(let objects):
                completionHandler(objects)
            case .failure(let error):
                let logger = DiagnosticLogger.shared.forCategory("NightscoutUploader")
                logger.error(error)
                completionHandler([])
            }
        }
    }
}

extension DeviceDataManager {
    func enactBolus(units: Double, at startDate: Date = Date(), completion: @escaping (_ error: Error?) -> Void) {
        guard let pumpManager = pumpManager else {
            completion(LoopError.configurationError(.pumpManager))
            return
        }

        pumpManager.enactBolus(units: units, at: startDate, willRequest: { (dose) in
            self.loopManager.addRequestedBolus(dose, completion: nil)
        }) { (result) in
            switch result {
            case .failure(let error):
                self.log.error(error)
                NotificationManager.sendBolusFailureNotification(for: error, units: units, at: startDate)
                completion(error)
            case .success(let dose):
                self.loopManager.addConfirmedBolus(dose) {
                    completion(nil)
                }
            }
        }
    }
}

extension DeviceDataManager {
    func deleteTestingPumpData() {
        assertingDebugOnly {
            guard let testingPumpManager = pumpManager as? TestingPumpManager else {
                assertionFailure("\(#function) should be invoked only when a testing pump manager is in use")
                return
            }
            let devicePredicate = HKQuery.predicateForObjects(from: [testingPumpManager.testingDevice])

            // DoseStore.deleteAllPumpEvents first syncs the events to the health store,
            // so HKHealthStore.deleteObjects catches any that were still in the cache.
            let doseStore = loopManager.doseStore
            let healthStore = doseStore.insulinDeliveryStore.healthStore
            doseStore.deleteAllPumpEvents { doseStoreError in
                if doseStoreError != nil {
                    healthStore.deleteObjects(of: doseStore.sampleType!, predicate: devicePredicate) { success, deletedObjectCount, error in
                        // errors are already logged through the store, so we'll ignore them here
                    }
                }
            }
        }
    }

    func deleteTestingCGMData() {
        assertingDebugOnly {
            guard let testingCGMManager = cgmManager as? TestingCGMManager else {
                assertionFailure("\(#function) should be invoked only when a testing CGM manager is in use")
                return
            }
            let predicate = HKQuery.predicateForObjects(from: [testingCGMManager.testingDevice])
            loopManager.glucoseStore.purgeGlucoseSamples(matchingCachePredicate: nil, healthKitPredicate: predicate) { success, count, error in
                // result already logged through the store, so ignore the error here
            }
        }
    }
}

// MARK: - LoopDataManagerDelegate
extension DeviceDataManager: LoopDataManagerDelegate {
    func loopDataManager(_ manager: LoopDataManager, roundBasalRate unitsPerHour: Double) -> Double {
        guard let pumpManager = pumpManager else {
            return unitsPerHour
        }
        
        return pumpManager.roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
    }

    func loopDataManager(_ manager: LoopDataManager, roundBolusVolume units: Double) -> Double {
        guard let pumpManager = pumpManager else {
            return units
        }

        return pumpManager.roundToSupportedBolusVolume(units: units)
    }

    func loopDataManager(
        _ manager: LoopDataManager,
        didRecommendBasalChange basal: (recommendation: TempBasalRecommendation, date: Date),
        completion: @escaping (_ result: Result<DoseEntry>) -> Void
    ) {
        guard let pumpManager = pumpManager else {
            completion(.failure(LoopError.configurationError(.pumpManager)))
            return
        }

        log.default("LoopManager did recommend basal change")

        pumpManager.enactTempBasal(
            unitsPerHour: basal.recommendation.unitsPerHour,
            for: basal.recommendation.duration,
            completion: { result in
                switch result {
                case .success(let doseEntry):
                    completion(.success(doseEntry))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )
    }


}


// MARK: - CustomDebugStringConvertible
extension DeviceDataManager: CustomDebugStringConvertible {
    var debugDescription: String {
        return [
            Bundle.main.localizedNameAndVersion,
            "",
            "## DeviceDataManager",
            "* launchDate: \(launchDate)",
            "* lastError: \(String(describing: lastError))",
            "",
            cgmManager != nil ? String(reflecting: cgmManager!) : "cgmManager: nil",
            "",
            pumpManager != nil ? String(reflecting: pumpManager!) : "pumpManager: nil",
            "",
            String(reflecting: watchManager!),
            "",
            String(reflecting: statusExtensionManager!),
        ].joined(separator: "\n")
    }
}

extension Notification.Name {
    static let PumpManagerChanged = Notification.Name(rawValue:  "com.loopKit.notification.PumpManagerChanged")
}

