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
    let bluetoothProvider: BluetoothProvider
    weak var onboardingManager: OnboardingManager?

    /// Remember the launch date of the app for diagnostic reporting
    private let launchDate = Date()

    /// The last error recorded by a device manager
    /// Should be accessed only on the main queue
    private(set) var lastError: (date: Date, error: Error)?

    private var deviceLog: PersistentDeviceLog

    // MARK: - App-level responsibilities

    private var alertPresenter: AlertPresenter
    
    private var deliveryUncertaintyAlertManager: DeliveryUncertaintyAlertManager?
    
    @Published var cgmHasValidSensorSession: Bool

    @Published var pumpIsAllowingAutomation: Bool

    private let automaticDosingStatus: AutomaticDosingStatus

    var closedLoopDisallowedLocalizedDescription: String? {
        if !cgmHasValidSensorSession {
            return NSLocalizedString("Closed Loop requires an active CGM Sensor Session", comment: "The description text for the looping enabled switch cell when closed loop is not allowed because the sensor is inactive")
        } else if !pumpIsAllowingAutomation {
            return NSLocalizedString("Your pump is delivering a manual temporary basal rate.", comment: "The description text for the looping enabled switch cell when closed loop is not allowed because the pump is delivering a manual temp basal.")
        } else {
            return nil
        }
    }

    lazy private var cancellables = Set<AnyCancellable>()
    
    lazy var allowedInsulinTypes: [InsulinType] = {
        var allowed = InsulinType.allCases
        if !FeatureFlags.fiaspInsulinModelEnabled {
            allowed.remove(.fiasp)
        }
        if !FeatureFlags.lyumjevInsulinModelEnabled {
            allowed.remove(.lyumjev)
        }
        if !FeatureFlags.afrezzaInsulinModelEnabled {
            allowed.remove(.afrezza)
        }

        for insulinType in InsulinType.allCases {
            if !insulinType.pumpAdministerable {
                allowed.remove(insulinType)
            }
        }

        return allowed
    }()

    private var cgmStalenessMonitor: CGMStalenessMonitor

    private var displayGlucoseUnitObservers = WeakSynchronizedSet<DisplayGlucoseUnitObserver>()

    public private(set) var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable

    // MARK: - CGM

    var cgmManager: CGMManager? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))
            setupCGM()

            if cgmManager?.managerIdentifier != oldValue?.managerIdentifier {
                if let cgmManager = cgmManager {
                    analyticsServicesManager.cgmWasAdded(identifier: cgmManager.managerIdentifier)
                } else {
                    analyticsServicesManager.cgmWasRemoved()
                }
            }

            NotificationCenter.default.post(name: .CGMManagerChanged, object: self, userInfo: nil)
            rawCGMManager = cgmManager?.rawValue
            UserDefaults.appGroup?.clearLegacyCGMManagerRawValue()
        }
    }

    @PersistedProperty(key: "CGMManagerState")
    var rawCGMManager: CGMManager.RawValue?

    // MARK: - Pump

    var pumpManager: PumpManagerUI? {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))

            // If the current CGMManager is a PumpManager, we clear it out.
            if cgmManager is PumpManagerUI {
                cgmManager = nil
            }

            if pumpManager?.managerIdentifier != oldValue?.managerIdentifier {
                if let pumpManager = pumpManager {
                    analyticsServicesManager.pumpWasAdded(identifier: pumpManager.managerIdentifier)
                } else {
                    analyticsServicesManager.pumpWasRemoved()
                }
            }

            setupPump()

            NotificationCenter.default.post(name: .PumpManagerChanged, object: self, userInfo: nil)

            rawPumpManager = pumpManager?.rawValue
            UserDefaults.appGroup?.clearLegacyPumpManagerRawValue()

        }
    }

    @PersistedProperty(key: "PumpManagerState")
    var rawPumpManager: PumpManager.RawValue?

    
    var doseEnactor = DoseEnactor()
    
    // MARK: Stores
    let healthStore: HKHealthStore
    
    let carbStore: CarbStore
    
    let doseStore: DoseStore
    
    let glucoseStore: GlucoseStore

    private let cacheStore: PersistenceController

    let dosingDecisionStore: DosingDecisionStore
    
    /// All the HealthKit types to be read by stores
    private var readTypes: Set<HKSampleType> {
        var readTypes: Set<HKSampleType> = []

        if FeatureFlags.observeHealthKitCarbSamplesFromOtherApps {
            readTypes.insert(carbStore.sampleType)
        }
        if FeatureFlags.observeHealthKitDoseSamplesFromOtherApps {
            readTypes.insert(doseStore.sampleType)
        }
        if FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps {
            readTypes.insert(glucoseStore.sampleType)
        }

        readTypes.insert(HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!)

        return readTypes
    }
    
    /// All the HealthKit types to be shared by stores
    private var shareTypes: Set<HKSampleType> {
        return Set([
            glucoseStore.sampleType,
            carbStore.sampleType,
            doseStore.sampleType,
        ])
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

    var settingsManager: SettingsManager

    var remoteDataServicesManager: RemoteDataServicesManager { return servicesManager.remoteDataServicesManager }

    var criticalEventLogExportManager: CriticalEventLogExportManager!

    var crashRecoveryManager: CrashRecoveryManager

    private(set) var pumpManagerHUDProvider: HUDProvider?

    private var trustedTimeChecker: TrustedTimeChecker

    // MARK: - WatchKit

    private var watchManager: WatchDataManager!

    // MARK: - Status Extension

    private var statusExtensionManager: ExtensionDataManager!

    // MARK: - Initialization

    private(set) var loopManager: LoopDataManager!

    init(pluginManager: PluginManager,
         alertManager: AlertManager,
         settingsManager: SettingsManager,
         loggingServicesManager: LoggingServicesManager,
         analyticsServicesManager: AnalyticsServicesManager,
         bluetoothProvider: BluetoothProvider,
         alertPresenter: AlertPresenter,
         automaticDosingStatus: AutomaticDosingStatus,
         cacheStore: PersistenceController,
         localCacheDuration: TimeInterval,
         overrideHistory: TemporaryScheduleOverrideHistory,
         trustedTimeChecker: TrustedTimeChecker)
    {

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

        self.pluginManager = pluginManager
        self.alertManager = alertManager
        self.bluetoothProvider = bluetoothProvider
        self.alertPresenter = alertPresenter
        
        self.healthStore = HKHealthStore()
        self.cacheStore = cacheStore
        self.settingsManager = settingsManager

        let absorptionTimes = LoopCoreConstants.defaultCarbAbsorptionTimes
        let sensitivitySchedule = settingsManager.latestSettings.insulinSensitivitySchedule
        
        self.carbStore = CarbStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitCarbSamplesFromOtherApps, // At some point we should let the user decide which apps they would like to import from.
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            defaultAbsorptionTimes: absorptionTimes,
            observationInterval: absorptionTimes.slow * 2,
            carbRatioSchedule: settingsManager.latestSettings.carbRatioSchedule,
            insulinSensitivitySchedule: sensitivitySchedule,
            overrideHistory: overrideHistory,
            carbAbsorptionModel: FeatureFlags.nonlinearCarbModelEnabled ? .nonlinear : .linear,
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )

        let insulinModelProvider: InsulinModelProvider
        if FeatureFlags.adultChildInsulinModelSelectionEnabled {
            insulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: settingsManager.latestSettings.defaultRapidActingModel?.presetForRapidActingInsulin)
        } else {
            insulinModelProvider = PresetInsulinModelProvider(defaultRapidActingModel: nil)
        }

        self.analyticsServicesManager = analyticsServicesManager
        
        self.doseStore = DoseStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitDoseSamplesFromOtherApps,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            insulinModelProvider: insulinModelProvider,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            basalProfile: settingsManager.latestSettings.basalRateSchedule,
            insulinSensitivitySchedule: sensitivitySchedule,
            overrideHistory: overrideHistory,
            lastPumpEventsReconciliation: nil, // PumpManager is nil at this point. Will update this via addPumpEvents below
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )
        
        self.glucoseStore = GlucoseStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            observationInterval: .hours(24),
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )
        
        cgmStalenessMonitor = CGMStalenessMonitor()
        cgmStalenessMonitor.delegate = glucoseStore
        
        self.dosingDecisionStore = DosingDecisionStore(store: cacheStore, expireAfter: localCacheDuration)
        
        self.cgmHasValidSensorSession = false
        self.pumpIsAllowingAutomation = true
        self.automaticDosingStatus = automaticDosingStatus

        // HealthStorePreferredGlucoseUnitDidChange will be notified once the user completes the health access form. Set to .milligramsPerDeciliter until then
        displayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: glucoseStore.preferredUnit ?? .milligramsPerDeciliter)

        self.trustedTimeChecker = trustedTimeChecker

        crashRecoveryManager = CrashRecoveryManager(alertIssuer: alertManager)
        alertManager.addAlertResponder(managerIdentifier: crashRecoveryManager.managerIdentifier, alertResponder: crashRecoveryManager)

        if let pumpManagerRawValue = rawPumpManager ?? UserDefaults.appGroup?.legacyPumpManagerRawValue {
            pumpManager = pumpManagerFromRawValue(pumpManagerRawValue)
            // Update lastPumpEventsReconciliation on DoseStore
            if let lastSync = pumpManager?.lastSync {
                doseStore.addPumpEvents([], lastReconciliation: lastSync) { _ in }
            }
            if let status = pumpManager?.status {
                updatePumpIsAllowingAutomation(status: status)
            }
        } else {
            pumpManager = nil
        }

        if let cgmManagerRawValue = rawCGMManager ?? UserDefaults.appGroup?.legacyCGMManagerRawValue {
            cgmManager = cgmManagerFromRawValue(cgmManagerRawValue)

            // Handle case of PumpManager providing CGM
            if cgmManager == nil && pumpManagerTypeFromRawValue(cgmManagerRawValue) != nil {
                cgmManager = pumpManager as? CGMManager
            }
        }

        //TODO The instantiation of these non-device related managers should be moved to LoopAppManager, and then LoopAppManager can wire up the connections between them.
        statusExtensionManager = ExtensionDataManager(deviceDataManager: self, automaticDosingStatus: automaticDosingStatus)

        loopManager = LoopDataManager(
            lastLoopCompleted: ExtensionDataManager.lastLoopCompleted,
            basalDeliveryState: pumpManager?.status.basalDeliveryState,
            settings: settingsManager.loopSettings,
            overrideHistory: overrideHistory,
            analyticsServicesManager: analyticsServicesManager,
            localCacheDuration: localCacheDuration,
            doseStore: doseStore,
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            dosingDecisionStore: dosingDecisionStore,
            latestStoredSettingsProvider: settingsManager,
            pumpInsulinType: pumpManager?.status.insulinType,
            automaticDosingStatus: automaticDosingStatus,
            trustedTimeOffset: { trustedTimeChecker.detectedSystemTimeOffset }
        )
        cacheStore.delegate = loopManager
        loopManager.presetActivationObservers.append(alertManager)
        loopManager.presetActivationObservers.append(analyticsServicesManager)

        watchManager = WatchDataManager(deviceManager: self, healthStore: healthStore)

        let remoteDataServicesManager = RemoteDataServicesManager(
            alertStore: alertManager.alertStore,
            carbStore: carbStore,
            doseStore: doseStore,
            dosingDecisionStore: dosingDecisionStore,
            glucoseStore: glucoseStore,
            settingsStore: settingsManager.settingsStore,
            overrideHistory: overrideHistory,
            insulinDeliveryStore: doseStore.insulinDeliveryStore
        )
        

        settingsManager.remoteDataServicesManager = remoteDataServicesManager
        
        servicesManager = ServicesManager(
            pluginManager: pluginManager,
            alertManager: alertManager,
            analyticsServicesManager: analyticsServicesManager,
            loggingServicesManager: loggingServicesManager,
            remoteDataServicesManager: remoteDataServicesManager
        )

        let criticalEventLogs: [CriticalEventLog] = [settingsManager.settingsStore, glucoseStore, carbStore, dosingDecisionStore, doseStore, deviceLog, alertManager.alertStore]
        criticalEventLogExportManager = CriticalEventLogExportManager(logs: criticalEventLogs,
                                                                      directory: FileManager.default.exportsDirectoryURL,
                                                                      historicalDuration: Bundle.main.localCacheDuration)

        loopManager.delegate = self

        alertManager.alertStore.delegate = self
        carbStore.delegate = self
        doseStore.delegate = self
        dosingDecisionStore.delegate = self
        glucoseStore.delegate = self
        doseStore.insulinDeliveryStore.delegate = self
        remoteDataServicesManager.delegate = self
        
        setupPump()
        setupCGM()
                
        cgmStalenessMonitor.$cgmDataIsStale
            .combineLatest($cgmHasValidSensorSession)
            .map { $0 == false || $1 }
            .combineLatest($pumpIsAllowingAutomation)
            .map { $0 && $1 }
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .assign(to: \.automaticDosingStatus.isAutomaticDosingAllowed, on: self)
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(forName: .HealthStorePreferredGlucoseUnitDidChange, object: glucoseStore.healthStore, queue: nil) { [weak self] _ in
            guard let strongSelf = self else {
                return
            }

            if let preferredGlucoseUnit = strongSelf.glucoseStore.preferredUnit {
                strongSelf.displayGlucoseUnitObservable.displayGlucoseUnitDidChange(to: preferredGlucoseUnit)
                strongSelf.notifyObserversOfDisplayGlucoseUnitChange(to: preferredGlucoseUnit)
            }
        }
    }

    var availablePumpManagers: [PumpManagerDescriptor] {
        return pluginManager.availablePumpManagers + availableStaticPumpManagers
    }

    func setupPumpManager(withIdentifier identifier: String, initialSettings settings: PumpManagerSetupSettings, prefersToSkipUserInteraction: Bool) -> Swift.Result<SetupUIResult<PumpManagerViewController, PumpManager>, Error> {
        switch setupPumpManagerUI(withIdentifier: identifier, initialSettings: settings, prefersToSkipUserInteraction: prefersToSkipUserInteraction) {
        case .failure(let error):
            return .failure(error)
        case .success(let success):
            switch success {
            case .userInteractionRequired(let viewController):
                return .success(.userInteractionRequired(viewController))
            case .createdAndOnboarded(let pumpManagerUI):
                return .success(.createdAndOnboarded(pumpManagerUI))
            }
        }
    }

    struct UnknownPumpManagerIdentifierError: Error {}

    func setupPumpManagerUI(withIdentifier identifier: String, initialSettings settings: PumpManagerSetupSettings, prefersToSkipUserInteraction: Bool = false) -> Swift.Result<SetupUIResult<PumpManagerViewController, PumpManagerUI>, Error> {
        guard let pumpManagerUIType = pumpManagerTypeByIdentifier(identifier) else {
            return .failure(UnknownPumpManagerIdentifierError())
        }

        let result = pumpManagerUIType.setupViewController(initialSettings: settings, bluetoothProvider: bluetoothProvider, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures, prefersToSkipUserInteraction: prefersToSkipUserInteraction, allowedInsulinTypes: allowedInsulinTypes)
        if case .createdAndOnboarded(let pumpManagerUI) = result {
            pumpManagerOnboarding(didCreatePumpManager: pumpManagerUI)
            pumpManagerOnboarding(didOnboardPumpManager: pumpManagerUI)
        }

        return .success(result)
    }

    public func pumpManagerTypeByIdentifier(_ identifier: String) -> PumpManagerUI.Type? {
        return pluginManager.getPumpManagerTypeByIdentifier(identifier) ?? staticPumpManagersByIdentifier[identifier]
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
    
    private func checkPumpDataAndLoop() {
        guard !crashRecoveryManager.pendingCrashRecovery else {
            self.log.default("Loop paused pending crash recovery acknowledgement.")
            return
        }

        self.log.default("Asserting current pump data")
        guard let pumpManager = pumpManager else {
            // Run loop, even if pump is missing, to ensure stored dosing decision
            self.loopManager.loop()
            return
        }

        pumpManager.ensureCurrentPumpData() { (lastSync) in
            self.loopManager.loop()
        }
    }

    private func processCGMReadingResult(_ manager: CGMManager, readingResult: CGMReadingResult, completion: @escaping () -> Void) {
        switch readingResult {
        case .newData(let values):
            log.default("CGMManager:%{public}@ did update with %d values", String(describing: type(of: manager)), values.count)
            loopManager.addGlucoseSamples(values) { result in
                if !values.isEmpty {
                    DispatchQueue.main.async {
                        self.cgmStalenessMonitor.cgmGlucoseSamplesAvailable(values)
                    }
                }
                completion()
            }
        case .unreliableData:
            loopManager.receivedUnreliableCGMReading()
            completion()
        case .noData:
            log.default("CGMManager:%{public}@ did update with no data", String(describing: type(of: manager)))
            completion()
        case .error(let error):
            log.default("CGMManager:%{public}@ did update with error: %{public}@", String(describing: type(of: manager)), String(describing: error))
            self.setLastError(error: error)
            completion()
        }
        updatePumpManagerBLEHeartbeatPreference()
    }

    var availableCGMManagers: [CGMManagerDescriptor] {
        var availableCGMManagers = pluginManager.availableCGMManagers + availableStaticCGMManagers
        if let pumpManagerAsCGMManager = pumpManager as? CGMManager {
            availableCGMManagers.append(CGMManagerDescriptor(identifier: pumpManagerAsCGMManager.managerIdentifier, localizedTitle: pumpManagerAsCGMManager.localizedTitle))
        }
        return availableCGMManagers
    }

    func setupCGMManager(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool = false) -> Swift.Result<SetupUIResult<CGMManagerViewController, CGMManager>, Error> {
        if let cgmManager = setupCGMManagerFromPumpManager(withIdentifier: identifier) {
            return .success(.createdAndOnboarded(cgmManager))
        }

        switch setupCGMManagerUI(withIdentifier: identifier, prefersToSkipUserInteraction: prefersToSkipUserInteraction) {
        case .failure(let error):
            return .failure(error)
        case .success(let success):
            switch success {
            case .userInteractionRequired(let viewController):
                return .success(.userInteractionRequired(viewController))
            case .createdAndOnboarded(let cgmManagerUI):
                return .success(.createdAndOnboarded(cgmManagerUI))
            }
        }
    }

    struct UnknownCGMManagerIdentifierError: Error {}

    fileprivate func setupCGMManagerUI(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool) -> Swift.Result<SetupUIResult<CGMManagerViewController, CGMManagerUI>, Error> {
        guard let cgmManagerUIType = cgmManagerTypeByIdentifier(identifier) else {
            return .failure(UnknownCGMManagerIdentifierError())
        }

        let result = cgmManagerUIType.setupViewController(bluetoothProvider: bluetoothProvider, displayGlucoseUnitObservable: displayGlucoseUnitObservable, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures, prefersToSkipUserInteraction: prefersToSkipUserInteraction)
        if case .createdAndOnboarded(let cgmManagerUI) = result {
            cgmManagerOnboarding(didCreateCGMManager: cgmManagerUI)
            cgmManagerOnboarding(didOnboardCGMManager: cgmManagerUI)
        }

        return .success(result)
    }

    public func cgmManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type? {
        return pluginManager.getCGMManagerTypeByIdentifier(identifier) ?? staticCGMManagersByIdentifier[identifier] as? CGMManagerUI.Type
    }
    
    public func setupCGMManagerFromPumpManager(withIdentifier identifier: String) -> CGMManager? {
        guard identifier == pumpManager?.managerIdentifier, let cgmManager = pumpManager as? CGMManager else {
            return nil
        }

        // We have a pump that is a CGM!
        self.cgmManager = cgmManager
        return cgmManager
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
                self.deliveryUncertaintyAlertManager?.showAlert()
            }
        }
    }

    func getHealthStoreAuthorization(_ completion: @escaping (HKAuthorizationRequestStatus) -> Void) {
        healthStore.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { (authorizationRequestStatus, _) in
            completion(authorizationRequestStatus)
        }
    }
    
    // Get HealthKit authorization for all of the stores
    func authorizeHealthStore(_ completion: @escaping (HKAuthorizationRequestStatus) -> Void) {
        // Authorize all types at once for simplicity
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { (success, error) in
            if success {
                // Call the individual authorization methods to trigger query creation
                self.carbStore.authorize(toShare: true, read: FeatureFlags.observeHealthKitCarbSamplesFromOtherApps, { _ in })
                self.doseStore.insulinDeliveryStore.authorize(toShare: true, read: FeatureFlags.observeHealthKitDoseSamplesFromOtherApps, { _ in })
                self.glucoseStore.authorize(toShare: true, read: FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps, { _ in })
            }

            self.getHealthStoreAuthorization(completion)
        }
    }
}

private extension DeviceDataManager {
    func setupCGM() {
        dispatchPrecondition(condition: .onQueue(.main))

        cgmManager?.cgmManagerDelegate = self
        cgmManager?.delegateQueue = queue

        glucoseStore.managedDataInterval = cgmManager?.managedDataInterval
        glucoseStore.healthKitStorageDelay = cgmManager.map{ type(of: $0).healthKitStorageDelay } ?? 0

        updatePumpManagerBLEHeartbeatPreference()
        if let cgmManager = cgmManager {
            alertManager?.addAlertResponder(managerIdentifier: cgmManager.managerIdentifier,
                                            alertResponder: cgmManager)
            alertManager?.addAlertSoundVendor(managerIdentifier: cgmManager.managerIdentifier,
                                              soundVendor: cgmManager)            
            cgmHasValidSensorSession = cgmManager.cgmManagerStatus.hasValidSensorSession

            analyticsServicesManager.identifyCGMType(cgmManager.managerIdentifier)
        }

        if let cgmManagerUI = cgmManager as? CGMManagerUI {
            addDisplayGlucoseUnitObserver(cgmManagerUI)
        }
    }

    func setupPump() {
        dispatchPrecondition(condition: .onQueue(.main))

        pumpManager?.pumpManagerDelegate = self
        pumpManager?.delegateQueue = queue

        doseStore.device = pumpManager?.status.device
        pumpManagerHUDProvider = pumpManager?.hudProvider(bluetoothProvider: bluetoothProvider, colorPalette: .default, allowedInsulinTypes: allowedInsulinTypes)

        // Proliferate PumpModel preferences to DoseStore
        if let pumpRecordsBasalProfileStartEvents = pumpManager?.pumpRecordsBasalProfileStartEvents {
            doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
        }
        if let pumpManager = pumpManager {
            alertManager?.addAlertResponder(managerIdentifier: pumpManager.managerIdentifier,
                                                  alertResponder: pumpManager)
            alertManager?.addAlertSoundVendor(managerIdentifier: pumpManager.managerIdentifier,
                                                    soundVendor: pumpManager)
            
            deliveryUncertaintyAlertManager = DeliveryUncertaintyAlertManager(pumpManager: pumpManager, alertPresenter: alertPresenter)

            analyticsServicesManager.identifyPumpType(pumpManager.managerIdentifier)
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
    func enactBolus(units: Double, activationType: BolusActivationType, completion: @escaping (_ error: Error?) -> Void = { _ in }) {
        guard let pumpManager = pumpManager else {
            completion(LoopError.configurationError(.pumpManager))
            return
        }

        self.loopManager.addRequestedBolus(DoseEntry(type: .bolus, startDate: Date(), value: units, unit: .units, isMutable: true)) {
            pumpManager.enactBolus(units: units, activationType: activationType) { (error) in
                if let error = error {
                    self.log.error("%{public}@", String(describing: error))
                    switch error {
                    case .uncertainDelivery:
                        // Do not generate notification on uncertain delivery error
                        break
                    default:
                        // Do not generate notifications for automatic boluses that fail.
                        if !activationType.isAutomatic {
                            NotificationManager.sendBolusFailureNotification(for: error, units: units, at: Date(), activationType: activationType)
                        }
                    }
                    
                    self.loopManager.bolusRequestFailed(error) {
                        completion(error)
                    }
                } else {
                    self.loopManager.bolusConfirmed() {
                        completion(nil)
                    }
                }
            }
            // Trigger forecast/recommendation update for remote clients
            self.loopManager.updateRemoteRecommendation()
        }
    }
    
    func enactBolus(units: Double, activationType: BolusActivationType) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            enactBolus(units: units, activationType: activationType) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
        }
    }

    var pumpManagerStatus: PumpManagerStatus? {
        return pumpManager?.status
    }

    var cgmManagerStatus: CGMManagerStatus? {
        return cgmManager?.cgmManagerStatus
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

    func didBecomeActive() {
        updatePumpManagerBLEHeartbeatPreference()
    }

    func updatePumpManagerBLEHeartbeatPreference() {
        pumpManager?.setMustProvideBLEHeartbeat(pumpManagerMustProvideBLEHeartbeat)
    }
}

// MARK: - DeviceManagerDelegate
extension DeviceDataManager: DeviceManagerDelegate {

    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        deviceLog.log(managerIdentifier: manager.managerIdentifier, deviceIdentifier: deviceIdentifier, type: type, message: message, completion: completion)
    }
    
    var allowDebugFeatures: Bool {
        FeatureFlags.allowDebugFeatures // NOTE: DEBUG FEATURES - DEBUG AND TEST ONLY
    }
}

// MARK: - AlertIssuer
extension DeviceDataManager: AlertIssuer {
    static let managerIdentifier = "DeviceDataManager"

    func issueAlert(_ alert: Alert) {
        alertManager?.issueAlert(alert)
    }

    func retractAlert(identifier: Alert.Identifier) {
        alertManager?.retractAlert(identifier: identifier)
    }
}

// MARK: - PersistedAlertStore
extension DeviceDataManager: PersistedAlertStore {
    func doesIssuedAlertExist(identifier: Alert.Identifier, completion: @escaping (Swift.Result<Bool, Error>) -> Void) {
        precondition(alertManager != nil)
        alertManager.doesIssuedAlertExist(identifier: identifier, completion: completion)
    }
    func lookupAllUnretracted(managerIdentifier: String, completion: @escaping (Swift.Result<[PersistedAlert], Error>) -> Void) {
        precondition(alertManager != nil)
        alertManager.lookupAllUnretracted(managerIdentifier: managerIdentifier, completion: completion)
    }
    
    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String, completion: @escaping (Swift.Result<[PersistedAlert], Error>) -> Void) {
        precondition(alertManager != nil)
        alertManager.lookupAllUnacknowledgedUnretracted(managerIdentifier: managerIdentifier, completion: completion)
    }

    func recordRetractedAlert(_ alert: Alert, at date: Date) {
        precondition(alertManager != nil)
        alertManager.recordRetractedAlert(alert, at: date)
    }
}

// MARK: - CGMManagerDelegate
extension DeviceDataManager: CGMManagerDelegate {
    func cgmManagerWantsDeletion(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(queue))

        log.default("CGM manager with identifier '%{public}@' wants deletion", manager.managerIdentifier)

        DispatchQueue.main.async {
            if let cgmManagerUI = self.cgmManager as? CGMManagerUI {
                self.removeDisplayGlucoseUnitObserver(cgmManagerUI)
            }
            self.cgmManager = nil
            self.displayGlucoseUnitObservers.cleanupDeallocatedElements()
            self.settingsManager.storeSettings()
        }
    }

    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        dispatchPrecondition(condition: .onQueue(queue))
        processCGMReadingResult(manager, readingResult: readingResult) {
            self.checkPumpDataAndLoop()
        }
    }

    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(queue))
        return glucoseStore.latestGlucose?.startDate
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        rawCGMManager = manager.rawValue
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

// MARK: - CGMManagerOnboardingDelegate

extension DeviceDataManager: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager cgmManager: CGMManagerUI) {
        log.default("CGM manager with identifier '%{public}@' created", cgmManager.managerIdentifier)
        self.cgmManager = cgmManager
    }

    func cgmManagerOnboarding(didOnboardCGMManager cgmManager: CGMManagerUI) {
        precondition(cgmManager.isOnboarded)
        log.default("CGM manager with identifier '%{public}@' onboarded", cgmManager.managerIdentifier)

        DispatchQueue.main.async {
            self.refreshDeviceData()
            self.settingsManager.storeSettings()
        }
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

        rawPumpManager = pumpManager.rawValue
    }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ did fire heartbeat", String(describing: type(of: pumpManager)))
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
                self.processCGMReadingResult(cgmManager, readingResult: result) {
                    if self.loopManager.lastLoopCompleted == nil || self.loopManager.lastLoopCompleted!.timeIntervalSinceNow < -.minutes(6) {
                        self.checkPumpDataAndLoop()
                    }
                    completion?()
                }
            }
        }
    }
    
    func refreshDeviceData() {
        refreshCGM() {
            self.queue.async {
                guard let pumpManager = self.pumpManager, pumpManager.isOnboarded else {
                    return
                }
                pumpManager.ensureCurrentPumpData(completion: nil)
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
        
        if let newBatteryValue = status.pumpBatteryChargeRemaining,
           let oldBatteryValue = oldStatus.pumpBatteryChargeRemaining,
           newBatteryValue - oldBatteryValue >= LoopConstants.batteryReplacementDetectionThreshold {
            analyticsServicesManager.pumpBatteryWasReplaced()
        }

        if status.basalDeliveryState != oldStatus.basalDeliveryState {
            loopManager.basalDeliveryState = status.basalDeliveryState
        }

        updatePumpIsAllowingAutomation(status: status)

        // Update the pump-schedule based settings
        loopManager.setScheduleTimeZone(status.timeZone)
        
        if status.insulinType != oldStatus.insulinType {
            loopManager.pumpInsulinType = status.insulinType
        }
        
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

    func updatePumpIsAllowingAutomation(status: PumpManagerStatus) {
        if case .tempBasal(let dose) = status.basalDeliveryState, !(dose.automatic ?? true), dose.endDate > Date() {
            pumpIsAllowingAutomation = false
        } else {
            pumpIsAllowingAutomation = true
        }
    }

    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) {
    }
    
    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(queue))

        log.default("Pump manager with identifier '%{public}@' will deactivate", pumpManager.managerIdentifier)

        DispatchQueue.main.async {
            self.pumpManager = nil
            self.deliveryUncertaintyAlertManager = nil
            self.settingsManager.storeSettings()
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
    }

    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent], lastReconciliation: Date?, completion: @escaping (_ error: Error?) -> Void) {
        dispatchPrecondition(condition: .onQueue(queue))
        log.default("PumpManager:%{public}@ hasNewPumpEvents (lastReconciliation = %{public}@)", String(describing: type(of: pumpManager)), String(describing: lastReconciliation))

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
            }
        }
    }

    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        dispatchPrecondition(condition: .onQueue(queue))
        return doseStore.pumpEventQueryAfterDate
    }

    var automaticDosingEnabled: Bool {
        automaticDosingStatus.automaticDosingEnabled
    }
}

// MARK: - PumpManagerOnboardingDelegate

extension DeviceDataManager: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        log.default("Pump manager with identifier '%{public}@' created", pumpManager.managerIdentifier)
        self.pumpManager = pumpManager
    }

    func pumpManagerOnboarding(didOnboardPumpManager pumpManager: PumpManagerUI) {
        precondition(pumpManager.isOnboarded)
        log.default("Pump manager with identifier '%{public}@' onboarded", pumpManager.managerIdentifier)

        DispatchQueue.main.async {
            self.refreshDeviceData()
            self.settingsManager.storeSettings()
        }
    }

    func pumpManagerOnboarding(didPauseOnboarding pumpManager: PumpManagerUI) {
        
    }
}

// MARK: - AlertStoreDelegate
extension DeviceDataManager: AlertStoreDelegate {

    func alertStoreHasUpdatedAlertData(_ alertStore: AlertStore) {
        remoteDataServicesManager.alertStoreHasUpdatedAlertData(alertStore)
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

// MARK: - InsulinDeliveryStoreDelegate
extension DeviceDataManager: InsulinDeliveryStoreDelegate {

    func insulinDeliveryStoreHasUpdatedDoseData(_ insulinDeliveryStore: InsulinDeliveryStore) {
        remoteDataServicesManager.insulinDeliveryStoreHasUpdatedDoseData(insulinDeliveryStore)
    }

}

// MARK: - TestingPumpManager
extension DeviceDataManager {
    func deleteTestingPumpData(completion: ((Error?) -> Void)? = nil) {
        guard let testingPumpManager = pumpManager as? TestingPumpManager else {
            completion?(nil)
            return
        }

        let devicePredicate = HKQuery.predicateForObjects(from: [testingPumpManager.testingDevice])
        let insulinDeliveryStore = doseStore.insulinDeliveryStore
        
        doseStore.resetPumpData { doseStoreError in
            guard doseStoreError == nil else {
                completion?(doseStoreError!)
                return
            }

            guard !self.doseStore.sharingDenied else {
                // only clear cache since access to health kit is denied
                insulinDeliveryStore.purgeCachedInsulinDeliveryObjects() { error in
                    completion?(error)
                }
                return
            }
            
            insulinDeliveryStore.purgeAllDoseEntries(healthKitPredicate: devicePredicate) { error in
                completion?(error)
            }
        }
    }

    func deleteTestingCGMData(completion: ((Error?) -> Void)? = nil) {
        guard let testingCGMManager = cgmManager as? TestingCGMManager else {
            assertionFailure("\(#function) should be invoked only when a testing CGM manager is in use")
            return
        }
        
        guard !glucoseStore.sharingDenied else {
            // only clear cache since access to health kit is denied
            glucoseStore.purgeCachedGlucoseObjects() { error in
                completion?(error)
            }
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
    func roundBasalRate(unitsPerHour: Double) -> Double {
        guard let pumpManager = pumpManager else {
            return unitsPerHour
        }

        return pumpManager.roundToSupportedBasalRate(unitsPerHour: unitsPerHour)
    }

    func roundBolusVolume(units: Double) -> Double {
        guard let pumpManager = pumpManager else {
            return units
        }

        let rounded = pumpManager.roundToSupportedBolusVolume(units: units)
        self.log.default("Rounded %{public}@ to %{public}@", String(describing: units), String(describing: rounded))

        return rounded
    }
    
    func loopDataManager(_ manager: LoopDataManager, estimateBolusDuration units: Double) -> TimeInterval? {
        pumpManager?.estimatedDuration(toBolus: units)
    }

    func loopDataManager(
        _ manager: LoopDataManager,
        didRecommend automaticDose: (recommendation: AutomaticDoseRecommendation, date: Date),
        completion: @escaping (LoopError?) -> Void
    ) {
        guard let pumpManager = pumpManager else {
            completion(LoopError.configurationError(.pumpManager))
            return
        }
        
        guard !pumpManager.status.deliveryIsUncertain else {
            completion(LoopError.connectionError)
            return
        }

        log.default("LoopManager did recommend dose: %{public}@", String(describing: automaticDose.recommendation))

        crashRecoveryManager.dosingStarted(dose: automaticDose.recommendation)
        doseEnactor.enact(recommendation: automaticDose.recommendation, with: pumpManager) { pumpManagerError in
            completion(pumpManagerError.map { .pumpManagerError($0) })
            self.crashRecoveryManager.dosingFinished()
        }
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
        Task {
            let backgroundTask = await beginBackgroundTask(name: "Remote Data Upload")
            await handleRemoteNotification(notification)
            await endBackgroundTask(backgroundTask)
        }
    }
    
    func handleRemoteNotification(_ notification: [String: AnyObject]) async {
        
        defer {
            log.default("Remote Notification: Finished handling")
        }
        
        guard FeatureFlags.remoteCommandsEnabled else {
            log.error("Remote Notification: Remote Commands not enabled.")
            return
        }
        
        let command: RemoteCommand
        do {
            command = try await remoteDataServicesManager.commandFromPushNotification(notification)
        } catch {
            log.error("Remote Notification: Parse Error: %{public}@", String(describing: error))
            return
        }
        
        await handleRemoteCommand(command)
    }
    
    func handleRemoteCommand(_ command: RemoteCommand) async {
        
        log.default("Remote Notification: Handling command %{public}@", String(describing: command))
        
        switch command.action {
        case .temporaryScheduleOverride(let overrideAction):
            do {
                try command.validate()
                try await handleOverrideAction(overrideAction)
            } catch {
                log.error("Remote Notification: Override Action Error: %{public}@", String(describing: error))
            }
        case .cancelTemporaryOverride(let overrideCancelAction):
            do {
                try command.validate()
                try await handleOverrideCancelAction(overrideCancelAction)
            } catch {
                log.error("Remote Notification: Override Action Cancel Error: %{public}@", String(describing: error))
            }
        case .bolusEntry(let bolusAction):
            do {
                try command.validate()
                try await handleBolusAction(bolusAction)
            } catch {
                await NotificationManager.sendRemoteBolusFailureNotification(for: error, amount: bolusAction.amountInUnits)
                log.error("Remote Notification: Bolus Action Error: %{public}@", String(describing: error))
            }
        case .carbsEntry(let carbAction):
            do {
                try command.validate()
                try await handleCarbAction(carbAction)
            } catch {
                await NotificationManager.sendRemoteCarbEntryFailureNotification(for: error, amountInGrams: carbAction.amountInGrams)
                log.error("Remote Notification: Carb Action Error: %{public}@", String(describing: error))
            }
        }
    }
    
    //Remote Overrides
    
    func handleOverrideAction(_ action: OverrideAction) async throws {
        let remoteOverride = try action.toValidOverride(allowedPresets: loopManager.settings.overridePresets)
        await activateRemoteOverride(remoteOverride)
    }
    
    func handleOverrideCancelAction(_ action: OverrideCancelAction) async throws {
        await activateRemoteOverride(nil)
    }
    
    func activateRemoteOverride(_ remoteOverride: TemporaryScheduleOverride?) async {
        loopManager.mutateSettings { settings in settings.scheduleOverride = remoteOverride }
        await remoteDataServicesManager.triggerUpload(for: .overrides)
    }
    
    //Remote Bolus
    
    func handleBolusAction(_ action: BolusAction) async throws {
        let validBolusAmount = try action.toValidBolusAmount(maximumBolus: loopManager.settings.maximumBolus)
        try await self.enactBolus(units: validBolusAmount, activationType: .manualNoRecommendation)
        await remoteDataServicesManager.triggerUpload(for: .dose)
        self.analyticsServicesManager.didBolus(source: "Remote", units: validBolusAmount)
    }
    
    //Remote Carb Entry
    
    func handleCarbAction(_ action: CarbAction) async throws {
        let candidateCarbEntry = try action.toValidCarbEntry(defaultAbsorptionTime: carbStore.defaultAbsorptionTimes.medium,
                                                                  minAbsorptionTime: LoopConstants.minCarbAbsorptionTime,
                                                                  maxAbsorptionTime: LoopConstants.maxCarbAbsorptionTime,
                                                                  maxCarbEntryQuantity: LoopConstants.maxCarbEntryQuantity.doubleValue(for: .gram()),
                                                                  maxCarbEntryPastTime: LoopConstants.maxCarbEntryPastTime,
                                                                  maxCarbEntryFutureTime: LoopConstants.maxCarbEntryFutureTime
        )
        
        let _ = try await addRemoteCarbEntry(candidateCarbEntry)
        await remoteDataServicesManager.triggerUpload(for: .carb)
    }
    
    //Can't add this concurrency wrapper method to LoopKit due to the minimum iOS version
    func addRemoteCarbEntry(_ carbEntry: NewCarbEntry) async throws -> StoredCarbEntry {
        return try await withCheckedThrowingContinuation { continuation in
            carbStore.addCarbEntry(carbEntry) { result in
                switch result {
                case .success(let storedCarbEntry):
                    self.analyticsServicesManager.didAddCarbs(source: "Remote", amount: carbEntry.quantity.doubleValue(for: .gram()))
                    continuation.resume(returning: storedCarbEntry)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    //Background Uploads
    
    func beginBackgroundTask(name: String) async -> UIBackgroundTaskIdentifier? {
        var backgroundTask: UIBackgroundTaskIdentifier?
        backgroundTask = await UIApplication.shared.beginBackgroundTask(withName: name) {
            guard let backgroundTask = backgroundTask else {return}
            Task {
                await UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            
            self.log.error("Background Task Expired: %{public}@", name)
        }
        
        return backgroundTask
    }
    
    func endBackgroundTask(_ backgroundTask: UIBackgroundTaskIdentifier?) async {
        guard let backgroundTask else {return}
        await UIApplication.shared.endBackgroundTask(backgroundTask)
    }
}

// MARK: - Critical Event Log Export

extension DeviceDataManager {
    private static var criticalEventLogHistoricalExportBackgroundTaskIdentifier: String { "com.loopkit.background-task.critical-event-log.historical-export" }

    public static func registerCriticalEventLogHistoricalExportBackgroundTask(_ handler: @escaping (BGProcessingTask) -> Void) -> Bool {
        return BGTaskScheduler.shared.register(forTaskWithIdentifier: criticalEventLogHistoricalExportBackgroundTaskIdentifier, using: nil) { handler($0 as! BGProcessingTask) }
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
            let request = BGProcessingTaskRequest(identifier: Self.criticalEventLogHistoricalExportBackgroundTaskIdentifier)
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

        settingsManager.settingsStore.generateSimulatedHistoricalSettingsObjects() { error in
            guard error == nil else {
                completion(error)
                return
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
                self.loopManager.purgeHistoricalCoreData { error in
                    guard error == nil else {
                        completion(error)
                        return
                    }
                    self.settingsManager.purgeHistoricalSettingsObjects(completion: completion)
                }
            }
        }
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


//MARK: TherapySettingsViewModelDelegate
struct CancelTempBasalFailedError: LocalizedError {
    let reason: Error?
    
    var errorDescription: String? {
        return String(format: NSLocalizedString("%@%@ was unable to cancel your current temporary basal rate, which is higher than the new Max Basal limit you have set. This may result in higher insulin delivery than desired.\n\nConsider suspending insulin delivery manually and then immediately resuming to enact basal delivery with the new limit in place.",
                                                comment: "Alert text for failing to cancel temp basal (1: reason description, 2: app name)"),
                      reasonString, Bundle.main.bundleDisplayName)
    }
    
    private var reasonString: String {
        let paragraphEnd = ".\n\n"
        if let localizedError = reason as? LocalizedError {
            let errors = [localizedError.errorDescription, localizedError.failureReason, localizedError.recoverySuggestion].compactMap { $0 }
            if !errors.isEmpty {
                return errors.joined(separator: ". ") + paragraphEnd
            }
        }
        return reason.map { $0.localizedDescription + paragraphEnd } ?? ""
    }
}

//MARK: - RemoteDataServicesManagerDelegate protocol conformance

extension DeviceDataManager : RemoteDataServicesManagerDelegate {
    var shouldSyncToRemoteService: Bool {
        guard let cgmManager = cgmManager else {
            return true
        }
        return cgmManager.shouldSyncToRemoteService
    }
}

extension DeviceDataManager: TherapySettingsViewModelDelegate {
    
    func syncBasalRateSchedule(items: [RepeatingScheduleValue<Double>], completion: @escaping (Swift.Result<BasalRateSchedule, Error>) -> Void) {
        pumpManager?.syncBasalRateSchedule(items: items, completion: completion)
    }
    
    func syncDeliveryLimits(deliveryLimits: DeliveryLimits, completion: @escaping (Swift.Result<DeliveryLimits, Error>) -> Void) {
        // FIRST we need to check to make sure if we have to cancel temp basal first
        loopManager.maxTempBasalSavePreflight(unitsPerHour: deliveryLimits.maximumBasalRate?.doubleValue(for: .internationalUnitsPerHour)) { [weak self] error in
            if let error = error {
                completion(.failure(CancelTempBasalFailedError(reason: error)))
            } else if let pumpManager = self?.pumpManager {
                pumpManager.syncDeliveryLimits(limits: deliveryLimits, completion: completion)
            } else {
                completion(.success(deliveryLimits))
            }
        }
    }
    
    func saveCompletion(therapySettings: TherapySettings) {

        loopManager.mutateSettings { settings in
            settings.glucoseTargetRangeSchedule = therapySettings.glucoseTargetRangeSchedule
            settings.preMealTargetRange = therapySettings.correctionRangeOverrides?.preMeal
            settings.legacyWorkoutTargetRange = therapySettings.correctionRangeOverrides?.workout
            settings.suspendThreshold = therapySettings.suspendThreshold
            settings.basalRateSchedule = therapySettings.basalRateSchedule
            settings.maximumBasalRatePerHour = therapySettings.maximumBasalRatePerHour
            settings.maximumBolus = therapySettings.maximumBolus
            settings.defaultRapidActingModel = therapySettings.defaultRapidActingModel
            settings.carbRatioSchedule = therapySettings.carbRatioSchedule
            settings.insulinSensitivitySchedule = therapySettings.insulinSensitivitySchedule
        }
    }
    
    func pumpSupportedIncrements() -> PumpSupportedIncrements? {
        return pumpManager.map {
            PumpSupportedIncrements(basalRates: $0.supportedBasalRates,
                                    bolusVolumes: $0.supportedBolusVolumes,
                                    maximumBolusVolumes: $0.supportedMaximumBolusVolumes,
                                    maximumBasalScheduleEntryCount: $0.maximumBasalScheduleEntryCount)
        }
    }
}

extension DeviceDataManager {
    func addDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver) {
        let queue = DispatchQueue.main
        displayGlucoseUnitObservers.insert(observer, queue: queue)
        if let displayGlucoseUnit = glucoseStore.preferredUnit {
            queue.async {
                observer.displayGlucoseUnitDidChange(to: displayGlucoseUnit)
            }
        }
    }

    func removeDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver) {
        displayGlucoseUnitObservers.removeElement(observer)
    }

    func notifyObserversOfDisplayGlucoseUnitChange(to displayGlucoseUnit: HKUnit) {
        self.displayGlucoseUnitObservers.forEach {
            $0.displayGlucoseUnitDidChange(to: displayGlucoseUnit)
        }
    }
}

extension DeviceDataManager: DeviceSupportDelegate {
    var availableSupports: [SupportUI] { [cgmManager, pumpManager].compactMap { $0 as? SupportUI } }

    func generateDiagnosticReport(_ completion: @escaping (_ report: String) -> Void) {
        self.loopManager.generateDiagnosticReport { (loopReport) in

            let logDurationHours = 84.0

            self.alertManager.getStoredEntries(startDate: Date() - .hours(logDurationHours)) { (alertReport) in
                self.deviceLog.getLogEntries(startDate: Date() - .hours(logDurationHours)) { (result) in
                    let deviceLogReport: String
                    switch result {
                    case .failure(let error):
                        deviceLogReport = "Error fetching entries: \(error)"
                    case .success(let entries):
                        deviceLogReport = entries.map { "* \($0.timestamp) \($0.managerIdentifier) \($0.deviceIdentifier ?? "") \($0.type) \($0.message)" }.joined(separator: "\n")
                    }

                    let report = [
                        "## Build Details",
                        "* appNameAndVersion: \(Bundle.main.localizedNameAndVersion)",
                        "* profileExpiration: \(Bundle.main.profileExpirationString)",
                        "* gitRevision: \(Bundle.main.gitRevision ?? "N/A")",
                        "* gitBranch: \(Bundle.main.gitBranch ?? "N/A")",
                        "* workspaceGitRevision: \(Bundle.main.workspaceGitRevision ?? "N/A")",
                        "* workspaceGitBranch: \(Bundle.main.workspaceGitBranch ?? "N/A")",
                        "* sourceRoot: \(Bundle.main.sourceRoot ?? "N/A")",
                        "* buildDateString: \(Bundle.main.buildDateString ?? "N/A")",
                        "* xcodeVersion: \(Bundle.main.xcodeVersion ?? "N/A")",
                        "",
                        "## FeatureFlags",
                        "\(FeatureFlags)",
                        "",
                        alertReport,
                        "",
                        "## DeviceDataManager",
                        "* launchDate: \(self.launchDate)",
                        "* lastError: \(String(describing: self.lastError))",
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
                        ].joined(separator: "\n")

                    completion(report)
                }
            }
        }
    }
}

extension DeviceDataManager: DeviceStatusProvider {}

extension DeviceDataManager {
    var detectedSystemTimeOffset: TimeInterval { trustedTimeChecker.detectedSystemTimeOffset }
}
