//
//  DeviceDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import BackgroundTasks
import HealthKit
import LoopKit
import LoopKitUI
import LoopCore
import LoopTestingKit
import UserNotifications
import Combine

final class DeviceDataManager {

    private let queue = DispatchQueue(label: "com.loopkit.DeviceManagerQueue", qos: .utility)

    private let log = DiagnosticLog(category: "DeviceDataManager")

    let pluginManager: PluginManager
    weak var alertManager: AlertManager!

    /// Remember the launch date of the app for diagnostic reporting
    private let launchDate = Date()

    private(set) var testingScenariosManager: TestingScenariosManager?

    /// The last error recorded by a device manager
    /// Should be accessed only on the main queue
    private(set) var lastError: (date: Date, error: Error)?

    /// The last time a BLE heartbeat was received and acted upon.
    private var lastBLEDrivenUpdate = Date.distantPast

    private var deviceLog: PersistentDeviceLog

    var bluetoothState: BluetoothStateManager.BluetoothState = .other
    
    // MARK: - App-level responsibilities

    private var rootViewController: UIViewController
    
    private var deliveryUncertaintyAlertManager: DeliveryUncertaintyAlertManager?
    
    @Published var cgmHasValidSensorSession: Bool

    @Published public var isClosedLoopAllowed: Bool
    
    @Published public var isClosedLoop: Bool
    
    lazy private var cancellables = Set<AnyCancellable>()

    private var cgmStalenessMonitor: CGMStalenessMonitor

    // MARK: - CGM

    var cgmManager: CGMManager? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            setupCGM()
            NotificationCenter.default.post(name: .CGMManagerChanged, object: self, userInfo: nil)
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
    
    // MARK: Stores
    let healthStore: HKHealthStore
    
    let carbStore: CarbStore
    
    let doseStore: DoseStore
    
    let glucoseStore: GlucoseStore
    
    private let cacheStore: PersistenceController
    
    let dosingDecisionStore: DosingDecisionStore
    
    let settingsStore: SettingsStore
    
    /// All the HealthKit types to be read by stores
    private var readTypes: Set<HKSampleType> {
        return Set([
            glucoseStore.sampleType,
            carbStore.sampleType,
            doseStore.sampleType,
            HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!
        ].compactMap { $0 })
    }
    
    /// All the HealthKit types to be shared by stores
    private var shareTypes: Set<HKSampleType> {
        return Set([
            glucoseStore.sampleType,
            carbStore.sampleType,
            doseStore.sampleType,
        ].compactMap { $0 })
    }

    var sleepDataAuthorizationRequired: Bool {
        return carbStore.healthStore.authorizationStatus(for: HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!) == .notDetermined
    }
    
    var sleepDataSharingDenied: Bool {
        return carbStore.healthStore.authorizationStatus(for: HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!) == .sharingDenied
    }

    /// True if any stores require HealthKit authorization
    var authorizationRequired: Bool {
        return glucoseStore.authorizationRequired ||
               carbStore.authorizationRequired ||
               doseStore.authorizationRequired ||
               sleepDataAuthorizationRequired
    }

    /// True if the user has explicitly denied access to any stores' HealthKit types
    private var sharingDenied: Bool {
        return glucoseStore.sharingDenied ||
               carbStore.sharingDenied ||
               doseStore.sharingDenied ||
               sleepDataSharingDenied
    }

    // MARK: Services

    private(set) var servicesManager: ServicesManager!

    var analyticsServicesManager: AnalyticsServicesManager

    var loggingServicesManager: LoggingServicesManager

    var remoteDataServicesManager: RemoteDataServicesManager { return servicesManager.remoteDataServicesManager }

    var criticalEventLogExportManager: CriticalEventLogExportManager!

    private(set) var pumpManagerHUDProvider: HUDProvider?

    // MARK: - WatchKit

    private var watchManager: WatchDataManager!

    // MARK: - Status Extension

    private var statusExtensionManager: ExtensionDataManager!

    // MARK: - Initialization

    private(set) var loopManager: LoopDataManager!

    init(pluginManager: PluginManager, alertManager: AlertManager, bluetoothStateManager: BluetoothStateManager, rootViewController: UIViewController) {
        let localCacheDuration = Bundle.main.localCacheDuration

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
        deviceLog = PersistentDeviceLog(storageFile: deviceLogDirectory.appendingPathComponent("Storage.sqlite"), maxEntryAge: localCacheDuration)

        loggingServicesManager = LoggingServicesManager()
        analyticsServicesManager = AnalyticsServicesManager()

        self.pluginManager = pluginManager
        self.alertManager = alertManager
        self.rootViewController = rootViewController
        
        self.healthStore = HKHealthStore()
        self.cacheStore = PersistenceController.controllerInAppGroupDirectory()
        
        let absorptionTimes = LoopCoreConstants.defaultCarbAbsorptionTimes
        let sensitivitySchedule = UserDefaults.appGroup?.insulinSensitivitySchedule
        let overrideHistory = UserDefaults.appGroup?.overrideHistory ?? TemporaryScheduleOverrideHistory.init()
        
        self.carbStore = CarbStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitSamplesFromOtherApps,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            defaultAbsorptionTimes: absorptionTimes,
            observationInterval: absorptionTimes.slow * 2,
            carbRatioSchedule: UserDefaults.appGroup?.carbRatioSchedule,
            insulinSensitivitySchedule: sensitivitySchedule,
            overrideHistory: overrideHistory,
            carbAbsorptionModel: FeatureFlags.nonlinearCarbModelEnabled ? .nonlinear : .linear,
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )
        
        self.doseStore = DoseStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitSamplesFromOtherApps,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            insulinModel: UserDefaults.appGroup?.insulinModelSettings?.model,
            basalProfile: UserDefaults.appGroup?.basalRateSchedule,
            insulinSensitivitySchedule: sensitivitySchedule,
            overrideHistory: overrideHistory,
            lastPumpEventsReconciliation: pumpManager?.lastReconciliation,
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )
        
        self.glucoseStore = GlucoseStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitSamplesFromOtherApps,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            observationInterval: .hours(24),
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )
        
        cgmStalenessMonitor = CGMStalenessMonitor()
        cgmStalenessMonitor.delegate = glucoseStore
        
        self.dosingDecisionStore = DosingDecisionStore(store: cacheStore, expireAfter: localCacheDuration)
        self.settingsStore = SettingsStore(store: cacheStore, expireAfter: localCacheDuration)
        
        self.cgmHasValidSensorSession = false
        self.isClosedLoop = false
        self.isClosedLoopAllowed = false
        
        bluetoothStateManager.addBluetoothStateObserver(self)

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

        statusExtensionManager = ExtensionDataManager(deviceDataManager: self)

        loopManager = LoopDataManager(
            lastLoopCompleted: statusExtensionManager.context?.lastLoopCompleted,
            basalDeliveryState: pumpManager?.status.basalDeliveryState,
            overrideHistory: overrideHistory,
            lastPumpEventsReconciliation: pumpManager?.lastReconciliation,
            analyticsServicesManager: analyticsServicesManager,
            localCacheDuration: localCacheDuration,
            doseStore: doseStore,
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            dosingDecisionStore: dosingDecisionStore,
            settingsStore: settingsStore,
            alertPresenter: alertManager
        )
        cacheStore.delegate = loopManager
        
        watchManager = WatchDataManager(deviceManager: self, healthStore: healthStore)

        let remoteDataServicesManager = RemoteDataServicesManager(
            carbStore: carbStore,
            doseStore: doseStore,
            dosingDecisionStore: dosingDecisionStore,
            glucoseStore: glucoseStore,
            settingsStore: settingsStore
        )

        servicesManager = ServicesManager(
            pluginManager: pluginManager,
            analyticsServicesManager: analyticsServicesManager,
            loggingServicesManager: loggingServicesManager,
            remoteDataServicesManager: remoteDataServicesManager,
            dataManager: loopManager
        )

        let criticalEventLogs: [CriticalEventLog] = [settingsStore, glucoseStore, carbStore, dosingDecisionStore, doseStore, deviceLog, alertManager.alertStore]
        criticalEventLogExportManager = CriticalEventLogExportManager(logs: criticalEventLogs,
                                                                      directory: FileManager.default.exportsDirectoryURL,
                                                                      historicalDuration: Bundle.main.localCacheDuration)

        if FeatureFlags.scenariosEnabled {
            testingScenariosManager = LocalTestingScenariosManager(deviceManager: self)
        }

        loopManager.delegate = self

        carbStore.delegate = self
        doseStore.delegate = self
        dosingDecisionStore.delegate = self
        glucoseStore.delegate = self
        settingsStore.delegate = self

        setupPump()
        setupCGM()
                
        cgmStalenessMonitor.$cgmDataIsStale
            .combineLatest($cgmHasValidSensorSession)
            .map { $0 == false || $1 }
            .assign(to: \.isClosedLoopAllowed, on: self)
            .store(in: &cancellables)

        $isClosedLoopAllowed
            .combineLatest(loopManager.$settings)
            .map { $0 && $1.dosingEnabled }
            .assign(to: \.isClosedLoop, on: self)
            .store(in: &cancellables)
        
        // Turn off preMeal when going into closed loop off mode
        // The dispatch is necessary in case this is coming from a didSet already on the settings struct.
        $isClosedLoop
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { if !$0 { self.loopManager.settings.clearOverride(matching: .preMeal) } }
            .store(in: &cancellables)
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

    private func processCGMReadingResult(_ manager: CGMManager, readingResult: CGMReadingResult) {
        switch readingResult {
        case .newData(let values):
            log.default("CGMManager:%{public}@ did update with %d values", String(describing: type(of: manager)), values.count)

            loopManager.addGlucoseSamples(values) { result in
                self.log.default("Asserting current pump data")
                self.pumpManager?.ensureCurrentPumpData(completion: nil)
                if !values.isEmpty {
                    DispatchQueue.main.async {
                        self.cgmStalenessMonitor.cgmGlucoseSamplesAvailable(values)
                    }
                }
            }
        case .noData:
            log.default("CGMManager:%{public}@ did update with no data", String(describing: type(of: manager)))

            pumpManager?.ensureCurrentPumpData(completion: nil)
        case .error(let error):
            log.default("CGMManager:%{public}@ did update with error: %{public}@", String(describing: type(of: manager)), String(describing: error))

            self.setLastError(error: error)
            log.default("Asserting current pump data")
            pumpManager?.ensureCurrentPumpData(completion: nil)
        }

        updatePumpManagerBLEHeartbeatPreference()
    }

    var availableCGMManagers: [AvailableDevice] {
        var availableCGMManagers = pluginManager.availableCGMManagers + availableStaticCGMManagers
        if let pumpManagerAsCGMManager = pumpManager as? CGMManager {
            availableCGMManagers.append(AvailableDevice(identifier: pumpManagerAsCGMManager.managerIdentifier, localizedTitle: pumpManagerAsCGMManager.localizedTitle, providesOnboarding: false))
        }
        return availableCGMManagers
    }

    public func cgmManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type? {
        return pluginManager.getCGMManagerTypeByIdentifier(identifier) ?? staticCGMManagersByIdentifier[identifier] as? CGMManagerUI.Type
    }
    
    public typealias SetupCGMCompletion = (CGMManager?) -> Void
    public func maybeSetupCGMManager(_ identifier: String, setupClosure: (CGMManagerUI.Type) -> Void) {
        if identifier == pumpManager?.managerIdentifier, let cgmManager = pumpManager as? CGMManager {
            // We have a pump that is a CGM!
            self.cgmManager = cgmManager
        } else if let cgmManagerType = cgmManagerTypeByIdentifier(identifier) {
            setupClosure(cgmManagerType)
        }
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
    
    func checkDeliveryUncertaintyState() {
        if let pumpManager = pumpManager, pumpManager.status.deliveryIsUncertain {
            DispatchQueue.main.async {
                self.deliveryUncertaintyAlertManager!.showAlert()
            }
        }
    }
    
    // Get HealthKit authorization for all of the stores
    func authorizeHealthStore(_ completion: @escaping () -> Void) {
        // Authorize all types at once for simplicity
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { (success, error) in
            if success {
                // Call the individual authorization methods to trigger query creation
                self.carbStore.authorize(toShare: true, { _ in })
                self.doseStore.insulinDeliveryStore.authorize(toShare: true, { _ in })
                self.glucoseStore.authorize(toShare: true, { _ in })
            }

            completion()
        }
    }

    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void) {
        self.loopManager.generateDiagnosticReport { (loopReport) in

            self.alertManager.getStoredEntries(startDate: Date() - .hours(48)) { (alertReport) in

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
                        "* profileExpiration: \(Bundle.main.profileExpirationString)",
                        "",
                        "## FeatureFlags",
                        "\(FeatureFlags)",
                        "",
                        "## DeviceDataManager",
                        "* launchDate: \(self.launchDate)",
                        "* lastError: \(String(describing: self.lastError))",
                        "* lastBLEDrivenUpdate: \(self.lastBLEDrivenUpdate)",
                        "",
                        "cacheStore: \(String(reflecting: self.cacheStore))",
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
                        alertReport
                        ].joined(separator: "\n")

                    completion(report)
                }
            }
        }
    }
}

private extension DeviceDataManager {
    func setupCGM() {
        dispatchPrecondition(condition: .onQueue(.main))

        cgmManager?.cgmManagerDelegate = self
        cgmManager?.delegateQueue = queue

        glucoseStore.managedDataInterval = cgmManager?.managedDataInterval

        updatePumpManagerBLEHeartbeatPreference()
        if let cgmManager = cgmManager {
            alertManager?.addAlertResponder(managerIdentifier: cgmManager.managerIdentifier,
                                            alertResponder: cgmManager)
            alertManager?.addAlertSoundVendor(managerIdentifier: cgmManager.managerIdentifier,
                                              soundVendor: cgmManager)            
            cgmHasValidSensorSession = cgmManager.cgmStatus.hasValidSensorSession
        }
        
    }

    func setupPump() {
        dispatchPrecondition(condition: .onQueue(.main))

        pumpManager?.pumpManagerDelegate = self
        pumpManager?.delegateQueue = queue

        doseStore.device = pumpManager?.status.device
        pumpManagerHUDProvider = pumpManager?.hudProvider(insulinTintColor: .insulinTintColor, guidanceColors: .default)

        // Proliferate PumpModel preferences to DoseStore
        if let pumpRecordsBasalProfileStartEvents = pumpManager?.pumpRecordsBasalProfileStartEvents {
            doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
        }
        if let pumpManager = pumpManager {
            alertManager?.addAlertResponder(managerIdentifier: pumpManager.managerIdentifier,
                                                  alertResponder: pumpManager)
            alertManager?.addAlertSoundVendor(managerIdentifier: pumpManager.managerIdentifier,
                                                    soundVendor: pumpManager)
            
            deliveryUncertaintyAlertManager = DeliveryUncertaintyAlertManager(pumpManager: pumpManager, rootViewController: rootViewController)
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
    func enactBolus(units: Double, at startDate: Date = Date(), completion: @escaping (_ error: Error?) -> Void = { _ in }) {
        guard let pumpManager = pumpManager else {
            completion(LoopError.configurationError(.pumpManager))
            return
        }

        self.loopManager.addRequestedBolus(DoseEntry(type: .bolus, startDate: Date(), value: units, unit: .units), completion: nil)
        pumpManager.enactBolus(units: units, at: startDate) { (result) in
            switch result {
            case .failure(let error):
                self.log.error("%{public}@", String(describing: error))
                switch error {
                case .uncertainDelivery:
                    // Do not generate notification on uncertain delivery error
                    break
                default:
                    NotificationManager.sendBolusFailureNotification(for: error, units: units, at: startDate)
                }
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

    func glucoseDisplay(for glucose: GlucoseSampleValue?) -> GlucoseDisplayable? {
        guard let glucose = glucose else {
            return cgmManager?.glucoseDisplay
        }
        
        guard FeatureFlags.cgmManagerCategorizeManualGlucoseRangeEnabled else {
            // Using Dexcom default glucose thresholds to categorize a glucose range
            let urgentLowGlucoseThreshold = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 55)
            let lowGlucoseThreshold = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)
            let highGlucoseThreshold = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)
            
            let glucoseRangeCategory: GlucoseRangeCategory
            switch glucose.quantity {
            case ...urgentLowGlucoseThreshold:
                glucoseRangeCategory = .urgentLow
            case urgentLowGlucoseThreshold..<lowGlucoseThreshold:
                glucoseRangeCategory = .low
            case lowGlucoseThreshold..<highGlucoseThreshold:
                glucoseRangeCategory = .normal
            default:
                glucoseRangeCategory = .high
            }
            
            if glucose.wasUserEntered {
                return ManualGlucoseDisplay(glucoseRangeCategory: glucoseRangeCategory)
            } else {
                var glucoseDisplay = GlucoseDisplay(cgmManager?.glucoseDisplay)
                glucoseDisplay?.glucoseRangeCategory = glucoseRangeCategory
                return glucoseDisplay
            }
        }
        
        if glucose.wasUserEntered {
            // the CGM manager needs to determine the glucose range category for a manual glucose based on its managed glucose thresholds
            let glucoseRangeCategory = (cgmManager as? CGMManagerUI)?.glucoseRangeCategory(for: glucose)
            return ManualGlucoseDisplay(glucoseRangeCategory: glucoseRangeCategory)
        } else {
            return cgmManager?.glucoseDisplay
        }
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
extension DeviceDataManager: AlertPresenter {
    static let managerIdentifier = "DeviceDataManager"

    func issueAlert(_ alert: Alert) {
        alertManager?.issueAlert(alert)
    }

    func retractAlert(identifier: Alert.Identifier) {
        alertManager?.retractAlert(identifier: identifier)
    }

    static var pumpBatteryLowAlertIdentifier: Alert.Identifier {
        return Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "PumpBatteryLow")
    }

    public var pumpBatteryLowAlert: Alert {
        let title = NSLocalizedString("Pump Battery Low", comment: "The notification title for a low pump battery")
        let body = NSLocalizedString("Change the pump battery immediately", comment: "The notification alert describing a low pump battery")
        let content = Alert.Content(title: title,
                                    body: body,
                                    acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        return Alert(identifier: DeviceDataManager.pumpBatteryLowAlertIdentifier,
                     foregroundContent: content,
                     backgroundContent: content,
                     trigger: .immediate)
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

    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(queue))
        lastBLEDrivenUpdate = Date()
        processCGMReadingResult(manager, readingResult: readingResult);
    }

    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(queue))
        return glucoseStore.latestGlucose?.startDate
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        UserDefaults.appGroup?.cgmManagerRawValue = manager.rawValue
    }

    func credentialStoragePrefix(for manager: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        return UUID().uuidString
    }
    
    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        DispatchQueue.main.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
        }
    }
}

extension DeviceDataManager: CGMManagerSetupViewControllerDelegate {
    func cgmManagerSetupViewController(_ cgmManagerSetupViewController: CGMManagerSetupViewController, didSetUpCGMManager cgmManager: CGMManagerUI) {
        self.cgmManager = cgmManager
    }
}

// MARK: - PumpManagerDelegate
extension DeviceDataManager: PumpManagerDelegate {
    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did adjust pump clock by %fs", String(describing: type(of: pumpManager)), adjustment)

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

        refreshCGM()
    }
    
    private func refreshCGM(_ completion: (() -> Void)? = nil) {        
        guard let cgmManager = cgmManager else {
            completion?()
            return
        }

        cgmManager.fetchNewDataIfNeeded { (result) in
            if case .newData = result {
                self.analyticsServicesManager.didFetchNewCGMData()
            }

            self.queue.async {
                self.processCGMReadingResult(cgmManager, readingResult: result)
                completion?()
            }
        }
    }
    
    func refreshDeviceData() {
        refreshCGM() {
            self.queue.async {
                self.pumpManager?.ensureCurrentPumpData(completion: nil)
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

        doseStore.device = status.device

        if let newBatteryValue = status.pumpBatteryChargeRemaining {

            if newBatteryValue != oldStatus.pumpBatteryChargeRemaining,
               newBatteryValue == 0
            {
                issueAlert(pumpBatteryLowAlert)
            }

            if let oldBatteryValue = oldStatus.pumpBatteryChargeRemaining, newBatteryValue - oldBatteryValue >= LoopConstants.batteryReplacementDetectionThreshold {
                retractAlert(identifier: DeviceDataManager.pumpBatteryLowAlertIdentifier)
                analyticsServicesManager.pumpBatteryWasReplaced()
            }
        }

        if status.basalDeliveryState != oldStatus.basalDeliveryState {
            loopManager.basalDeliveryState = status.basalDeliveryState
        }

        // Update the pump-schedule based settings
        loopManager.setScheduleTimeZone(status.timeZone)
        
        if status.deliveryIsUncertain != oldStatus.deliveryIsUncertain {
            DispatchQueue.main.async {
                if status.deliveryIsUncertain {
                    self.deliveryUncertaintyAlertManager?.showAlert()
                } else {
                    self.deliveryUncertaintyAlertManager?.clearAlert()
                }
            }
        }
    }
    
    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(queue))

        log.default("PumpManager:%{public}@ will deactivate", String(describing: type(of: pumpManager)))

        doseStore.resetPumpData(completion: nil)
        DispatchQueue.main.async {
            self.pumpManager = nil
        }
    }

    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did update pumpRecordsBasalProfileStartEvents to %{public}@", String(describing: type(of: pumpManager)), String(describing: pumpRecordsBasalProfileStartEvents))

        doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
    }

    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.error("PumpManager:%{public}@ did error: %{public}@", String(describing: type(of: pumpManager)), String(describing: error))

        setLastError(error: error)
        loopManager.storeDosingDecision(withDate: Date(), withError: error)
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

    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date, completion: @escaping (_ result: Swift.Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void) {
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
        return doseStore.pumpEventQueryAfterDate
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
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }

        guard let testingPumpManager = pumpManager as? TestingPumpManager else {
            assertionFailure("\(#function) should be invoked only when a testing pump manager is in use")
            return
        }

        let devicePredicate = HKQuery.predicateForObjects(from: [testingPumpManager.testingDevice])
        let insulinDeliveryStore = doseStore.insulinDeliveryStore
        
        let healthStore = insulinDeliveryStore.healthStore
        doseStore.resetPumpData { doseStoreError in
            guard doseStoreError == nil else {
                completion?(doseStoreError!)
                return
            }

            healthStore.deleteObjects(of: self.doseStore.sampleType!, predicate: devicePredicate) { success, deletedObjectCount, error in
                if success {
                    insulinDeliveryStore.test_lastBasalEndDate = nil
                }
                completion?(error)
            }
        }
    }

    func deleteTestingCGMData(completion: ((Error?) -> Void)? = nil) {
        guard FeatureFlags.scenariosEnabled else {
            fatalError("\(#function) should be invoked only when scenarios are enabled")
        }

        guard let testingCGMManager = cgmManager as? TestingCGMManager else {
            assertionFailure("\(#function) should be invoked only when a testing CGM manager is in use")
            return
        }

        let predicate = HKQuery.predicateForObjects(from: [testingCGMManager.testingDevice])
        glucoseStore.purgeAllGlucoseSamples(healthKitPredicate: predicate) { error in
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
        
        guard !pumpManager.status.deliveryIsUncertain else {
            completion(.failure(LoopError.connectionError))
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
    
    var automaticDosingEnabled: Bool {
        return isClosedLoop
    }
}

extension Notification.Name {
    static let PumpManagerChanged = Notification.Name(rawValue:  "com.loopKit.notification.PumpManagerChanged")
    static let CGMManagerChanged = Notification.Name(rawValue:  "com.loopKit.notification.CGMManagerChanged")
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

// MARK: - Critical Event Log Export

extension DeviceDataManager {
    private static var criticalEventLogHistoricalExportBackgroundTaskIdentifer: String { "com.loopkit.background-task.critical-event-log.historical-export" }

    public static func registerCriticalEventLogHistoricalExportBackgroundTask(_ handler: @escaping (BGProcessingTask) -> Void) -> Bool {
        return BGTaskScheduler.shared.register(forTaskWithIdentifier: criticalEventLogHistoricalExportBackgroundTaskIdentifer, using: nil) { handler($0 as! BGProcessingTask) }
    }

    public func handleCriticalEventLogHistoricalExportBackgroundTask(_ task: BGProcessingTask) {
        dispatchPrecondition(condition: .notOnQueue(.main))

        scheduleCriticalEventLogHistoricalExportBackgroundTask(isRetry: true)

        let exporter = criticalEventLogExportManager.createHistoricalExporter()

        task.expirationHandler = {
            self.log.default("Invoked critical event log historical export background task expiration handler - cancelling exporter")
            exporter.cancel()
        }

        DispatchQueue.global(qos: .background).async {
            exporter.export() { error in
                if let error = error {
                    self.log.error("Critical event log historical export errored: %{public}@", String(describing: error))
                }

                self.scheduleCriticalEventLogHistoricalExportBackgroundTask(isRetry: error != nil && !exporter.isCancelled)
                task.setTaskCompleted(success: error == nil)

                self.log.default("Completed critical event log historical export background task")
            }
        }
    }

    public func scheduleCriticalEventLogHistoricalExportBackgroundTask(isRetry: Bool = false) {
        do {
            let earliestBeginDate = isRetry ? criticalEventLogExportManager.retryExportHistoricalDate() : criticalEventLogExportManager.nextExportHistoricalDate()
            let request = BGProcessingTaskRequest(identifier: Self.criticalEventLogHistoricalExportBackgroundTaskIdentifer)
            request.earliestBeginDate = earliestBeginDate
            request.requiresExternalPower = true

            try BGTaskScheduler.shared.submit(request)

            log.default("Scheduled critical event log historical export background task: %{public}@", ISO8601DateFormatter().string(from: earliestBeginDate))
        } catch let error {
            #if IOS_SIMULATOR
            log.debug("Failed to schedule critical event log export background task due to running on simulator")
            #else
            log.error("Failed to schedule critical event log export background task: %{public}@", String(describing: error))
            #endif
        }
    }

    public func removeExportsDirectory() -> Error? {
        let fileManager = FileManager.default
        let exportsDirectoryURL = fileManager.exportsDirectoryURL

        guard fileManager.fileExists(atPath: exportsDirectoryURL.path) else {
            return nil
        }

        do {
            try fileManager.removeItem(at: exportsDirectoryURL)
        } catch let error {
            return error
        }

        return nil
    }
}

// MARK: - Simulated Core Data

extension DeviceDataManager {
    func generateSimulatedHistoricalCoreData(completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        self.loopManager.generateSimulatedHistoricalCoreData() { error in
            guard error == nil else {
                completion(error)
                return
            }
            self.deviceLog.generateSimulatedHistoricalDeviceLogEntries() { error in
                guard error == nil else {
                    completion(error)
                    return
                }
                self.alertManager.alertStore.generateSimulatedHistoricalStoredAlerts(completion: completion)
            }
        }
    }

    func purgeHistoricalCoreData(completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        alertManager.alertStore.purgeHistoricalStoredAlerts() { error in
            guard error == nil else {
                completion(error)
                return
            }
            self.deviceLog.purgeHistoricalDeviceLogEntries() { error in
                guard error == nil else {
                    completion(error)
                    return
                }
                self.loopManager.purgeHistoricalCoreData(completion: completion)
            }
        }
    }
}

//MARK: - Bluetooth State Manager Observation

extension DeviceDataManager: BluetoothStateManagerObserver {
    func bluetoothStateManager(_ bluetoothStateManager: BluetoothStateManager,
                               bluetoothStateDidUpdate bluetoothState: BluetoothStateManager.BluetoothState)
    {
        self.bluetoothState = bluetoothState
    }
}

fileprivate extension FileManager {
    var exportsDirectoryURL: URL {
        let applicationSupportDirectory = try! url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return applicationSupportDirectory.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("Exports")
    }
}

//MARK: - CGMStalenessMonitorDelegate protocol conformance

extension GlucoseStore : CGMStalenessMonitorDelegate { }


//MARK: - SupportInfoProvider protocol conformance

extension DeviceDataManager: SupportInfoProvider {
    
    public var localizedAppNameAndVersion: String {
        return Bundle.main.localizedNameAndVersion
    }
    
    public var pumpStatus: PumpManagerStatus? {
        return pumpManager?.status
    }
    
    public var cgmDevice: HKDevice? {
        return cgmManager?.device
    }
    
    public func generateIssueReport(completion: @escaping (String) -> Void) {
        generateDiagnosticReport(completion)
    }
    
    
}
