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

    private let log = DiagnosticLog(category: "DeviceDataManager")

    let pluginManager: PluginManager
    weak var deviceAlertManager: DeviceAlertManager?

    /// Remember the launch date of the app for diagnostic reporting
    private let launchDate = Date()

    private(set) var testingScenariosManager: TestingScenariosManager?

    /// The last error recorded by a device manager
    /// Should be accessed only on the main queue
    private(set) var lastError: (date: Date, error: Error)?

    /// The last time a BLE heartbeat was received and acted upon.
    private var lastBLEDrivenUpdate = Date.distantPast
    
    private var deviceLog: PersistentDeviceLog

    // MARK: - CGM

    var cgmManager: CGMManager? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            setupCGM()
            UserDefaults.appGroup?.cgmManagerRawValue = cgmManager?.rawValue
        }
    }
    
    // MARK: - Pump
    
    var pumpManager: PumpManagerUI? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            
            // If the current CGMManager is a PumpManager, we clear it out.
            if cgmManager is PumpManagerUI {
                cgmManager = nil
            }
            
            setupPump()
            
            NotificationCenter.default.post(name: .PumpManagerChanged, object: self, userInfo: nil)
            
            UserDefaults.appGroup?.pumpManagerRawValue = pumpManager?.rawValue
        }
    }

    private(set) var servicesManager: ServicesManager!

    var analyticsServicesManager: AnalyticsServicesManager

    var loggingServicesManager: LoggingServicesManager

    var remoteDataServicesManager: RemoteDataServicesManager { return servicesManager.remoteDataServicesManager }

    private(set) var pumpManagerHUDProvider: HUDProvider?

    // MARK: - WatchKit

    private var watchManager: WatchDataManager!

    // MARK: - Status Extension

    private var statusExtensionManager: StatusExtensionDataManager!

    // MARK: - Initialization

    private(set) var loopManager: LoopDataManager!
    
    init(pluginManager: PluginManager, deviceAlertManager: DeviceAlertManager) {
        
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        deviceLog = PersistentDeviceLog(storageFile: documentsDirectory.appendingPathComponent("DeviceLog.sqlite"))

        loggingServicesManager = LoggingServicesManager()
        analyticsServicesManager = AnalyticsServicesManager()
        
        self.pluginManager = pluginManager
        self.deviceAlertManager = deviceAlertManager

        if let pumpManagerRawValue = UserDefaults.appGroup?.pumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
        } else {
            pumpManager = nil
        }

        if let cgmManagerRawValue = UserDefaults.appGroup?.cgmManagerRawValue {
            cgmManager = cgmManagerFromRawValue(cgmManagerRawValue)
        } else if isCGMManagerValidPumpManager {
            self.cgmManager = pumpManager as? CGMManager
        }

        statusExtensionManager = StatusExtensionDataManager(deviceDataManager: self)

        loopManager = LoopDataManager(
            lastLoopCompleted: statusExtensionManager.context?.lastLoopCompleted,
            basalDeliveryState: pumpManager?.status.basalDeliveryState,
            lastPumpEventsReconciliation: pumpManager?.lastReconciliation,
            analyticsServicesManager: analyticsServicesManager
        )
        watchManager = WatchDataManager(deviceManager: self)
        
        let remoteDataServicesManager = RemoteDataServicesManager(
            carbStore: loopManager.carbStore,
            doseStore: loopManager.doseStore,
            dosingDecisionStore: loopManager.dosingDecisionStore,
            glucoseStore: loopManager.glucoseStore,
            settingsStore: loopManager.settingsStore
        )
        
        servicesManager = ServicesManager(
            pluginManager: pluginManager,
            analyticsServicesManager: analyticsServicesManager,
            loggingServicesManager: loggingServicesManager,
            remoteDataServicesManager: remoteDataServicesManager
        )


        if debugEnabled {
            testingScenariosManager = LocalTestingScenariosManager(deviceManager: self)
        }

        loopManager.delegate = self

        loopManager.carbStore.delegate = self
        loopManager.doseStore.delegate = self
        loopManager.dosingDecisionStore.delegate = self
        loopManager.glucoseStore.delegate = self
        loopManager.settingsStore.delegate = self

        setupPump()
        setupCGM()
    }

    var isCGMManagerValidPumpManager: Bool {
        guard let rawValue = UserDefaults.appGroup?.cgmManagerState else {
            return false
        }

        return pumpManagerTypeFromRawValue(rawValue) != nil
    }

    var availablePumpManagers: [AvailableDevice] {
        return pluginManager.availablePumpManagers + availableStaticPumpManagers
    }

    public func pumpManagerTypeByIdentifier(_ identifier: String) -> PumpManagerUI.Type? {
        return pluginManager.getPumpManagerTypeByIdentifier(identifier) ?? staticPumpManagersByIdentifier[identifier] as? PumpManagerUI.Type
    }

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return pumpManagerTypeByIdentifier(managerIdentifier)
    }

    func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
            let Manager = pumpManagerTypeFromRawValue(rawValue)
            else {
                return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }
    
    private func processCGMResult(_ manager: CGMManager, result: CGMResult) {
        switch result {
        case .newData(let values):
            log.default("CGMManager:%{public}@ did update with %d values", String(describing: type(of: manager)), values.count)

            loopManager.addGlucose(values) { result in
                self.log.default("Asserting current pump data")
                self.pumpManager?.assertCurrentPumpData()
            }
        case .noData:
            log.default("CGMManager:%{public}@ did update with no data", String(describing: type(of: manager)))
            
            pumpManager?.assertCurrentPumpData()
        case .error(let error):
            log.default("CGMManager:%{public}@ did update with error: %{public}@", String(describing: type(of: manager)), String(describing: error))
            
            self.setLastError(error: error)
            log.default("Asserting current pump data")
            pumpManager?.assertCurrentPumpData()
        }
        
        updatePumpManagerBLEHeartbeatPreference()
    }


    var availableCGMManagers: [AvailableDevice] {
        return pluginManager.availableCGMManagers + availableStaticCGMManagers
    }

    public func cgmManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type? {
        return pluginManager.getCGMManagerTypeByIdentifier(identifier) ?? staticCGMManagersByIdentifier[identifier] as? CGMManagerUI.Type
    }

    private func cgmManagerTypeFromRawValue(_ rawValue: [String: Any]) -> CGMManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        return cgmManagerTypeByIdentifier(managerIdentifier)
    }

    func cgmManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManagerUI? {
        guard let rawState = rawValue["state"] as? CGMManager.RawStateValue,
            let Manager = cgmManagerTypeFromRawValue(rawValue)
            else {
                return nil
        }

        return Manager.init(rawState: rawState) as? CGMManagerUI
    }
    
    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void) {
        self.loopManager.generateDiagnosticReport { (loopReport) in
            self.deviceLog.getLogEntries(startDate: Date() - .hours(48)) { (result) in
                let deviceLogReport: String
                switch result {
                case .failure(let error):
                    deviceLogReport = "Error fetching entries: \(error)"
                case .success(let entries):
                    deviceLogReport = entries.map { "* \($0.timestamp) \($0.managerIdentifier) \($0.deviceIdentifier ?? "") \($0.type) \($0.message)" }.joined(separator: "\n")
                }
                
                let report = [
                    Bundle.main.localizedNameAndVersion,
                    "* gitRevision: \(Bundle.main.gitRevision ?? "N/A")",
                    "* gitBranch: \(Bundle.main.gitBranch ?? "N/A")",
                    "* sourceRoot: \(Bundle.main.sourceRoot ?? "N/A")",
                    "* buildDateString: \(Bundle.main.buildDateString ?? "N/A")",
                    "* xcodeVersion: \(Bundle.main.xcodeVersion ?? "N/A")",
                    "",
                    "## FeatureFlags",
                    "\(FeatureFlags)",
                    "",
                    "## DeviceDataManager",
                    "* launchDate: \(self.launchDate)",
                    "* lastError: \(String(describing: self.lastError))",
                    "* lastBLEDrivenUpdate: \(self.lastBLEDrivenUpdate)",
                    "",
                    self.cgmManager != nil ? String(reflecting: self.cgmManager!) : "cgmManager: nil",
                    "",
                    self.pumpManager != nil ? String(reflecting: self.pumpManager!) : "pumpManager: nil",
                    "",
                    "## Device Communication Log",
                    deviceLogReport,
                    "",
                    String(reflecting: self.watchManager!),
                    "",
                    String(reflecting: self.statusExtensionManager!),
                    "",
                    loopReport,
                ].joined(separator: "\n")
                
                completion(report)
            }
        }
    }
}

private extension DeviceDataManager {
    func setupCGM() {
        dispatchPrecondition(condition: .onQueue(.main))

        cgmManager?.cgmManagerDelegate = self
        cgmManager?.delegateQueue = queue
        
        loopManager.glucoseStore.managedDataInterval = cgmManager?.managedDataInterval

        updatePumpManagerBLEHeartbeatPreference()
        if let cgmManager = cgmManager {
            deviceAlertManager?.addAlertResponder(managerIdentifier: cgmManager.managerIdentifier,
                                                  alertResponder: cgmManager)
            deviceAlertManager?.addAlertSoundVendor(managerIdentifier: cgmManager.managerIdentifier,
                                                    soundVendor: cgmManager)
        }
    }

    func setupPump() {
        dispatchPrecondition(condition: .onQueue(.main))

        pumpManager?.pumpManagerDelegate = self
        pumpManager?.delegateQueue = queue

        loopManager.doseStore.device = pumpManager?.status.device
        pumpManagerHUDProvider = pumpManager?.hudProvider()

        // Proliferate PumpModel preferences to DoseStore
        if let pumpRecordsBasalProfileStartEvents = pumpManager?.pumpRecordsBasalProfileStartEvents {
            loopManager?.doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
        }
        if let pumpManager = pumpManager {
            deviceAlertManager?.addAlertResponder(managerIdentifier: pumpManager.managerIdentifier,
                                                  alertResponder: pumpManager)
            deviceAlertManager?.addAlertSoundVendor(managerIdentifier: pumpManager.managerIdentifier,
                                                    soundVendor: pumpManager)
        }
    }

    func setLastError(error: Error) {
        DispatchQueue.main.async {
            self.lastError = (date: Date(), error: error)
        }
    }
}

// MARK: - Client API
extension DeviceDataManager {
    func enactBolus(units: Double, at startDate: Date = Date(), completion: @escaping (_ error: Error?) -> Void) {
        guard let pumpManager = pumpManager else {
            completion(LoopError.configurationError(.pumpManager))
            return
        }

        self.loopManager.addRequestedBolus(DoseEntry(type: .bolus, startDate: Date(), value: units, unit: .units), completion: nil)
        pumpManager.enactBolus(units: units, at: startDate, willRequest: { (dose) in
            // No longer used...
        }) { (result) in
            switch result {
            case .failure(let error):
                self.log.error("%{public}@", String(describing: error))
                NotificationManager.sendBolusFailureNotification(for: error, units: units, at: startDate)
                self.loopManager.bolusRequestFailed(error) {
                    completion(error)
                }
            case .success(let dose):
                self.loopManager.bolusConfirmed(dose) {
                    completion(nil)
                }
            }
        }
    }

    var pumpManagerStatus: PumpManagerStatus? {
        return pumpManager?.status
    }

    var sensorState: SensorDisplayable? {
        return cgmManager?.sensorState
    }

    func updatePumpManagerBLEHeartbeatPreference() {
        pumpManager?.setMustProvideBLEHeartbeat(pumpManagerMustProvideBLEHeartbeat)
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

        UNUserNotificationCenter.current().add(request)
    }

    func clearNotification(for manager: DeviceManager, identifier: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
    }
    
    func removeNotificationRequests(for manager: DeviceManager, identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        deviceLog.log(managerIdentifier: Swift.type(of: manager).managerIdentifier, deviceIdentifier: deviceIdentifier, type: type, message: message, completion: completion)
    }
}

// MARK: - UserAlertHandler
extension DeviceDataManager: DeviceAlertPresenter {

    func issueAlert(_ alert: DeviceAlert) {
        deviceAlertManager?.issueAlert(alert)
    }
    
    func removePendingAlert(identifier: DeviceAlert.Identifier) {
        deviceAlertManager?.removePendingAlert(identifier: identifier)
    }
    
    func removeDeliveredAlert(identifier: DeviceAlert.Identifier) {
        deviceAlertManager?.removeDeliveredAlert(identifier: identifier)
    }
}

// MARK: - CGMManagerDelegate
extension DeviceDataManager: CGMManagerDelegate {
    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        DispatchQueue.main.async {
            self.cgmManager = nil
        }
    }

    func cgmManager(_ manager: CGMManager, didUpdateWith result: CGMResult) {
        dispatchPrecondition(condition: .onQueue(queue))
        lastBLEDrivenUpdate = Date()
        processCGMResult(manager, result: result);
    }

    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(queue))
        return loopManager.glucoseStore.latestGlucose?.startDate
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        UserDefaults.appGroup?.cgmManagerRawValue = manager.rawValue
    }

    func credentialStoragePrefix(for manager: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        return UUID().uuidString
    }

}


// MARK: - PumpManagerDelegate
extension DeviceDataManager: PumpManagerDelegate {
    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did adjust pump block by %fs", String(describing: type(of: pumpManager)), adjustment)

        analyticsServicesManager.pumpTimeDidDrift(adjustment)
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did update state", String(describing: type(of: pumpManager)))

        UserDefaults.appGroup?.pumpManagerRawValue = pumpManager.rawValue
    }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did fire BLE heartbeat", String(describing: type(of: pumpManager)))

        let bleHeartbeatUpdateInterval: TimeInterval
        switch loopManager.lastLoopCompleted?.timeIntervalSinceNow {
        case .none:
            // If we haven't looped successfully, retry only every 5 minutes
            bleHeartbeatUpdateInterval = .minutes(5)
        case let interval? where interval < .minutes(-10):
            // If we haven't looped successfully in more than 10 minutes, retry only every 5 minutes
            bleHeartbeatUpdateInterval = .minutes(5)
        case let interval? where interval <= .minutes(-5):
            // If we haven't looped successfully in more than 5 minutes, retry every minute
            bleHeartbeatUpdateInterval = .minutes(1)
        case let interval?:
            // If we looped successfully less than 5 minutes ago, ignore the heartbeat.
            log.default("PumpManager:%{public}@ ignoring heartbeat. Last loop completed %{public}@ minutes ago", String(describing: type(of: pumpManager)), String(describing: interval.minutes))
            return
        }

        guard lastBLEDrivenUpdate.timeIntervalSinceNow <= -bleHeartbeatUpdateInterval else {
            log.default("PumpManager:%{public}@ ignoring heartbeat. Last update %{public}@", String(describing: type(of: pumpManager)), String(describing: lastBLEDrivenUpdate))
            return
        }
        lastBLEDrivenUpdate = Date()

        cgmManager?.fetchNewDataIfNeeded { (result) in
            if case .newData = result {
                self.analyticsServicesManager.didFetchNewCGMData()
            }

            if let manager = self.cgmManager {
                self.queue.async {
                    self.processCGMResult(manager, result: result)
                }
            }
        }
    }

    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        return pumpManagerMustProvideBLEHeartbeat
    }

    private var pumpManagerMustProvideBLEHeartbeat: Bool {
        /// Controls the management of the RileyLink timer tick, which is a reliably-changing BLE
        /// characteristic which can cause the app to wake. For most users, the G5 Transmitter and
        /// G4 Receiver are reliable as hearbeats, but users who find their resources extremely constrained
        /// due to greedy apps or older devices may choose to always enable the timer by always setting `true`
        return !(cgmManager?.providesBLEHeartbeat == true)
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did update status: %{public}@", String(describing: type(of: pumpManager)), String(describing: status))

        loopManager.doseStore.device = status.device

        if let newBatteryValue = status.pumpBatteryChargeRemaining {
            if newBatteryValue == 0 {
                NotificationManager.sendPumpBatteryLowNotification()
            } else {
                NotificationManager.clearPumpBatteryLowNotification()
            }

            if let oldBatteryValue = oldStatus.pumpBatteryChargeRemaining, newBatteryValue - oldBatteryValue >= loopManager.settings.batteryReplacementDetectionThreshold {
                analyticsServicesManager.pumpBatteryWasReplaced()
            }
        }

        if status.basalDeliveryState != oldStatus.basalDeliveryState {
            loopManager.basalDeliveryState = status.basalDeliveryState
        }

        // Update the pump-schedule based settings
        loopManager.setScheduleTimeZone(status.timeZone)
    }

    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(queue))

        log.default("PumpManager:%{public}@ will deactivate", String(describing: type(of: pumpManager)))

        loopManager.doseStore.resetPumpData()
        DispatchQueue.main.async {
            self.pumpManager = nil
        }
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did update pumpRecordsBasalProfileStartEvents to %{public}@", String(describing: type(of: pumpManager)), String(describing: pumpRecordsBasalProfileStartEvents))

        loopManager.doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
    }

    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.error("PumpManager:%{public}@ did error: %{public}@", String(describing: type(of: pumpManager)), String(describing: error))

        setLastError(error: error)
        loopManager.storeDosingDecision(withError: error)
    }

    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent], lastReconciliation: Date?, completion: @escaping (_ error: Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did read pump events", String(describing: type(of: pumpManager)))

        loopManager.addPumpEvents(events, lastReconciliation: lastReconciliation) { (error) in
            if let error = error {
                self.log.error("Failed to addPumpEvents to DoseStore: %{public}@", String(describing: error))
            }

            completion(error)

            if error == nil {
                NotificationCenter.default.post(name: .PumpEventsAdded, object: self, userInfo: nil)
            }
        }
    }

    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (_ result: PumpManagerResult<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool)>) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did read reservoir value", String(describing: type(of: pumpManager)))

        loopManager.addReservoirValue(units, at: date) { (result) in
            switch result {
            case .failure(let error):
                self.log.error("Failed to addReservoirValue: %{public}@", String(describing: error))
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
                        self.analyticsServicesManager.reservoirWasRewound()

                        NotificationManager.clearPumpReservoirNotification()
                    }
                }
            }
        }
    }

    func pumpManagerRecommendsLoop(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ recommends loop", String(describing: type(of: pumpManager)))
        loopManager.loop()
    }

    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        dispatchPrecondition(condition: .onQueue(queue))
        return loopManager.doseStore.pumpEventQueryAfterDate
    }
}

// MARK: - CarbStoreDelegate
extension DeviceDataManager: CarbStoreDelegate {
    
    func carbStoreHasUpdatedCarbData(_ carbStore: CarbStore) {
        remoteDataServicesManager.carbStoreHasUpdatedCarbData(carbStore)
    }
    
    func carbStore(_ carbStore: CarbStore, didError error: CarbStore.CarbStoreError) {}
    
}

// MARK: - DoseStoreDelegate
extension DeviceDataManager: DoseStoreDelegate {
    
    func doseStoreHasUpdatedDoseData(_ doseStore: DoseStore) {
        remoteDataServicesManager.doseStoreHasUpdatedDoseData(doseStore)
    }
    
    func doseStoreHasUpdatedPumpEventData(_ doseStore: DoseStore) {
        remoteDataServicesManager.doseStoreHasUpdatedPumpEventData(doseStore)
    }
    
}

// MARK: - DosingDecisionStoreDelegate
extension DeviceDataManager: DosingDecisionStoreDelegate {

    func dosingDecisionStoreHasUpdatedDosingDecisionData(_ dosingDecisionStore: DosingDecisionStore) {
        remoteDataServicesManager.dosingDecisionStoreHasUpdatedDosingDecisionData(dosingDecisionStore)
    }

}

// MARK: - GlucoseStoreDelegate
extension DeviceDataManager: GlucoseStoreDelegate {
    
    func glucoseStoreHasUpdatedGlucoseData(_ glucoseStore: GlucoseStore) {
        remoteDataServicesManager.glucoseStoreHasUpdatedGlucoseData(glucoseStore)
    }
    
}

// MARK: - SettingsStoreDelegate
extension DeviceDataManager: SettingsStoreDelegate {
    
    func settingsStoreHasUpdatedSettingsData(_ settingsStore: SettingsStore) {
        remoteDataServicesManager.settingsStoreHasUpdatedSettingsData(settingsStore)
    }
    
}

// MARK: - TestingPumpManager
extension DeviceDataManager {
    func deleteTestingPumpData(completion: ((Error?) -> Void)? = nil) {
        assertDebugOnly()

        guard let testingPumpManager = pumpManager as? TestingPumpManager else {
            assertionFailure("\(#function) should be invoked only when a testing pump manager is in use")
            return
        }

        let devicePredicate = HKQuery.predicateForObjects(from: [testingPumpManager.testingDevice])
        let doseStore = loopManager.doseStore
        let insulinDeliveryStore = doseStore.insulinDeliveryStore
        let healthStore = insulinDeliveryStore.healthStore
        doseStore.resetPumpData { doseStoreError in
            guard doseStoreError == nil else {
                completion?(doseStoreError!)
                return
            }

            healthStore.deleteObjects(of: doseStore.sampleType!, predicate: devicePredicate) { success, deletedObjectCount, error in
                if success {
                    insulinDeliveryStore.test_lastBasalEndDate = nil
                }
                completion?(error)
            }
        }
    }

    func deleteTestingCGMData(completion: ((Error?) -> Void)? = nil) {
        assertDebugOnly()

        guard let testingCGMManager = cgmManager as? TestingCGMManager else {
            assertionFailure("\(#function) should be invoked only when a testing CGM manager is in use")
            return
        }

        let predicate = HKQuery.predicateForObjects(from: [testingCGMManager.testingDevice])
        loopManager.glucoseStore.purgeGlucoseSamples(matchingCachePredicate: nil, healthKitPredicate: predicate) { success, count, error in
            completion?(error)
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

extension Notification.Name {
    static let PumpManagerChanged = Notification.Name(rawValue:  "com.loopKit.notification.PumpManagerChanged")
    static let PumpEventsAdded = Notification.Name(rawValue:  "com.loopKit.notification.PumpEventsAdded")
}

// MARK: - Remote Notification Handling
extension DeviceDataManager {
    func handleRemoteNotification(_ notification: [String: AnyObject]) {        
        if FeatureFlags.remoteOverridesEnabled {
            if let command = RemoteCommand(notification: notification, allowedPresets: loopManager.settings.overridePresets) {
                switch command {
                case .temporaryScheduleOverride(let override):
                    log.default("Enacting remote temporary override: %{public}@", String(describing: override))
                    loopManager.settings.scheduleOverride = override
                case .cancelTemporaryOverride:
                    log.default("Canceling temporary override from remote command")
                    loopManager.settings.scheduleOverride = nil
                }
            } else {
                log.info("Unhandled remote notification: %{public}@", String(describing: notification))
            }
        }
    }
}
