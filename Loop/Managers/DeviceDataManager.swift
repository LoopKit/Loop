//
//  DeviceDataManager.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 8/30/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import HealthKit
@preconcurrency import LoopKit
import LoopKitUI
import LoopCore
import LoopTestingKit
import UserNotifications
import Combine
import LoopKit

public enum DemoError: LocalizedError {
    case CommsError
}

@MainActor
protocol LoopControl {
    var lastLoopCompleted: Date? { get }
    var automatedTreatmentState: AutomatedTreatmentState? { get }
    func cancelActiveTempBasal(for reason: CancelActiveTempBasalReason) async throws
    func loop() async
}

protocol ActiveServicesProvider {
    var activeServices: [Service] { get }
}

protocol ActiveStatefulPluginsProvider {
    var activeStatefulPlugins: [StatefulPluggable] { get }
}


protocol UploadEventListener {
    func triggerUpload(for triggeringType: RemoteDataType)
}

@MainActor
final class DeviceDataManager {

    private let log = DiagnosticLog(category: "DeviceDataManager")

    let pluginManager: PluginManager
    weak var alertManager: AlertManager!
    let bluetoothProvider: BluetoothProvider
    weak var onboardingManager: OnboardingManager?

    /// Remember the launch date of the app for diagnostic reporting
    private let launchDate = Date()

    /// The last error recorded by a device manager
    private(set) var lastError: (date: Date, error: Error)?

    var deviceLog: PersistentDeviceLog

    // MARK: - App-level responsibilities

    private var alertPresenter: AlertPresenter
    
    private var deliveryUncertaintyAlertManager: DeliveryUncertaintyAlertManager?

    let glucoseAlertManager: GlucoseAlertManager
    
    @Published var cgmHasValidSensorSession: Bool

    private var cgmDeviceModel: String?

    @Published var pumpIsAllowingAutomation: Bool

    private var lastCGMLoopTrigger: Date = .distantPast

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
        if !FeatureFlags.apidraInsulinModelEnabled {
            allowed.remove(.apidra)
        }

        for insulinType in InsulinType.allCases {
            if !insulinType.pumpAdministerable {
                allowed.remove(insulinType)
            }
        }

        return allowed
    }()

    private var cgmStalenessMonitor: CGMStalenessMonitor

    var deviceWhitelist = DeviceWhitelist()

    // MARK: - CGM

    var cgmManager: CGMManager? {
        didSet {
            setupCGM()

            if cgmManager?.pluginIdentifier != oldValue?.pluginIdentifier {
                if let cgmManager = cgmManager {
                    analyticsServicesManager.cgmWasAdded(identifier: cgmManager.pluginIdentifier)
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

    var pumpManager: PumpManager? {
        didSet {
            // If the current CGMManager is a PumpManager, we clear it out.
            if cgmManager is PumpManagerUI {
                cgmManager = nil
            }

            if pumpManager?.pluginIdentifier != oldValue?.pluginIdentifier {
                if let pumpManager = pumpManager {
                    analyticsServicesManager.pumpWasAdded(identifier: pumpManager.pluginIdentifier)
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

    /// Set while a profile switch or save runs, so profile changes run one at a time.
    private(set) var therapyProfileChangeInProgress = false

    /// Issues the alerts about scheduled profile switches.
    weak var scheduledProfileSwitchAlertIssuer: AlertIssuer?
    
    // MARK: Stores
    let carbStore: CarbStore
    let doseStore: DoseStore
    let glucoseStore: GlucoseStore
    
    private let healthStore: HKHealthStore
    private let cacheStore: PersistenceController
    private let cgmEventStore: CgmEventStore

    /// All the HealthKit types to be read by stores
    private var readTypes: Set<HKSampleType> {
        var readTypes: Set<HKSampleType> = []

        if FeatureFlags.observeHealthKitCarbSamplesFromOtherApps {
            readTypes.insert(HealthKitSampleStore.carbType)
        }
        if FeatureFlags.observeHealthKitDoseSamplesFromOtherApps {
            readTypes.insert(HealthKitSampleStore.insulinQuantityType)
        }
        if FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps {
            readTypes.insert(HealthKitSampleStore.glucoseType)
        }

        readTypes.insert(HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!)

        return readTypes
    }
    
    /// All the HealthKit types to be shared by stores
    private var shareTypes: Set<HKSampleType> {
        return Set([
            HealthKitSampleStore.glucoseType,
            HealthKitSampleStore.carbType,
            HealthKitSampleStore.insulinQuantityType,
        ])
    }

    var sleepDataAuthorizationRequired: Bool {
        return healthStore.authorizationStatus(for: HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!) == .notDetermined
    }
    
    var sleepDataSharingDenied: Bool {
        return healthStore.authorizationStatus(for: HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!) == .sharingDenied
    }

    /// True if any stores require HealthKit authorization
    var authorizationRequired: Bool {
        return healthStore.authorizationStatus(for: HealthKitSampleStore.glucoseType) == .notDetermined ||
               healthStore.authorizationStatus(for: HealthKitSampleStore.carbType) == .notDetermined ||
               healthStore.authorizationStatus(for: HealthKitSampleStore.insulinQuantityType) == .notDetermined ||
               sleepDataAuthorizationRequired
    }

    // MARK: Services

    private var analyticsServicesManager: AnalyticsServicesManager
    private var uploadEventListener: UploadEventListener
    private var activeServicesProvider: ActiveServicesProvider

    // MARK: Misc Managers

    private let settingsManager: SettingsManager
    private let crashRecoveryManager: CrashRecoveryManager
    private let activeStatefulPluginsProvider: ActiveStatefulPluginsProvider

    private(set) var pumpManagerHUDProvider: HUDProvider?

    public private(set) var displayGlucosePreference: DisplayGlucosePreference

    private(set) var loopControl: LoopControl

    private weak var displayGlucoseUnitBroadcaster: DisplayGlucoseUnitBroadcaster?

    init(pluginManager: PluginManager,
         deviceLog: PersistentDeviceLog,
         alertManager: AlertManager,
         settingsManager: SettingsManager,
         healthStore: HKHealthStore,
         carbStore: CarbStore,
         doseStore: DoseStore,
         glucoseStore: GlucoseStore,
         cgmEventStore: CgmEventStore,
         uploadEventListener: UploadEventListener,
         crashRecoveryManager: CrashRecoveryManager,
         loopControl: LoopControl,
         analyticsServicesManager: AnalyticsServicesManager,
         activeServicesProvider: ActiveServicesProvider,
         activeStatefulPluginsProvider: ActiveStatefulPluginsProvider,
         bluetoothProvider: BluetoothProvider,
         alertPresenter: AlertPresenter,
         cacheStore: PersistenceController,
         localCacheDuration: TimeInterval,
         displayGlucosePreference: DisplayGlucosePreference,
         displayGlucoseUnitBroadcaster: DisplayGlucoseUnitBroadcaster
    ) {

        self.pluginManager = pluginManager
        self.deviceLog = deviceLog
        self.alertManager = alertManager
        self.scheduledProfileSwitchAlertIssuer = alertManager
        self.glucoseAlertManager = GlucoseAlertManager(alertIssuer: alertManager,
                                                       displayGlucosePreference: displayGlucosePreference)
        alertManager.addAlertSoundVendor(managerIdentifier: GlucoseAlertManager.managerIdentifier,
                                         soundVendor: self.glucoseAlertManager)
        alertManager.playsThroughSilent = { [weak glucoseAlertManager = self.glucoseAlertManager] alert in
            alert.identifier.managerIdentifier == GlucoseAlertManager.managerIdentifier &&
                glucoseAlertManager?.playsThroughSilent(for: alert.identifier.alertIdentifier) == true
        }
        self.settingsManager = settingsManager
        self.healthStore = healthStore
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.glucoseStore = glucoseStore
        self.cgmEventStore = cgmEventStore
        self.loopControl = loopControl
        self.analyticsServicesManager = analyticsServicesManager
        self.bluetoothProvider = bluetoothProvider
        self.alertPresenter = alertPresenter
        self.cacheStore = cacheStore
        self.crashRecoveryManager = crashRecoveryManager
        self.activeStatefulPluginsProvider = activeStatefulPluginsProvider
        self.uploadEventListener = uploadEventListener
        self.activeServicesProvider = activeServicesProvider
        self.displayGlucosePreference = displayGlucosePreference
        self.displayGlucoseUnitBroadcaster = displayGlucoseUnitBroadcaster

        cgmStalenessMonitor = CGMStalenessMonitor()
        cgmStalenessMonitor.delegate = glucoseStore

        cgmHasValidSensorSession = false
        pumpIsAllowingAutomation = true

        alertManager.alertStore.delegate = self
        carbStore.delegate = self
        doseStore.delegate = self
        glucoseStore.delegate = self
        cgmEventStore.delegate = self
        doseStore.insulinDeliveryStore.delegate = self

        Task {
            await cgmStalenessMonitor.checkCGMStaleness()
        }

        setupPump()
        setupCGM()
    }

    func instantiateDeviceManagers() {
        if let pumpManagerRawValue = rawPumpManager ?? UserDefaults.appGroup?.legacyPumpManagerRawValue {
            if let restoredPumpManager = pumpManagerFromRawValue(pumpManagerRawValue) {
                pumpManager = restoredPumpManager
                // Update lastPumpEventsReconciliation on DoseStore
                if let lastSync = pumpManager?.lastSync {
                    Task {
                        try? await doseStore.addPumpEvents([], lastReconciliation: lastSync)
                    }
                }
                if let status = pumpManager?.status {
                    updatePumpIsAllowingAutomation(status: status)
                }
            } else {
                // We have saved pump state, but its plugin couldn't be instantiated in this build (e.g.
                // the app was built without that pump manager plugin). Do NOT assign pumpManager = nil —
                // that fires the didSet, which writes rawPumpManager = nil and DELETES the persisted
                // PumpManagerState, permanently losing the pod pairing/session keys. Leave the saved
                // state on disk so a build that includes the plugin can restore it on a later launch.
                log.error("Saved pump manager plugin unavailable; preserving persisted PumpManagerState for a future launch")
            }
        } else {
            pumpManager = nil
        }

        if let cgmManagerRawValue = rawCGMManager ?? UserDefaults.appGroup?.legacyCGMManagerRawValue {
            if let restoredCGMManager = cgmManagerFromRawValue(cgmManagerRawValue) {
                cgmManager = restoredCGMManager
            } else if pumpManagerTypeFromRawValue(cgmManagerRawValue) != nil {
                // Handle case of PumpManager providing CGM
                cgmManager = pumpManager as? CGMManager
            } else {
                // Saved CGM state exists but its plugin couldn't be instantiated in this build. Don't
                // assign cgmManager = nil — that would delete the persisted CGMManagerState (same
                // footgun as the pump path above). Preserve it for a future launch with the plugin.
                log.error("Saved CGM manager plugin unavailable; preserving persisted CGMManagerState for a future launch")
            }
        }
    }

    var availablePumpManagers: [PumpManagerDescriptor] {
        var pumpManagers = pluginManager.availablePumpManagers + availableStaticPumpManagers
        
        pumpManagers = pumpManagers.filter({ pumpManager in
            guard !deviceWhitelist.pumpDevices.isEmpty else {
                return true
            }
            
            return deviceWhitelist.pumpDevices.contains(pumpManager.identifier)
        })
        
        return pumpManagers
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
    
    public func saveUpdatedBasalRateSchedule(_ basalRateSchedule: BasalRateSchedule) {
        var therapySettings = self.settingsManager.therapySettings
        therapySettings.basalRateSchedule = basalRateSchedule
        self.saveCompletion(therapySettings: therapySettings)
    }

    public func pumpManagerTypeByIdentifier(_ identifier: String) -> PumpManagerUI.Type? {
        return pluginManager.getPumpManagerTypeByIdentifier(identifier) ?? staticPumpManagersByIdentifier[identifier]
    }

    private func pumpManagerTypeFromRawValue(_ rawValue: [String: Any]) -> PumpManager.Type? {
        guard let managerIdentifier = rawValue["managerIdentifier"] as? String else {
            return nil
        }

        if let pumpManager = pumpManagerTypeByIdentifier(managerIdentifier) {
            return pumpManager
        }

        /// The pumpManager was not found for managerIdentifier. If this was for an "Omnipod" (OmniKit) or
        /// "Omnipod-DASH" (OmniBLE), have the universal "Omni" pumpManager (OmnipodKit) handle instead.
        let OmniStr = "Omni"
        if managerIdentifier.hasPrefix(OmniStr) {
            return pumpManagerTypeByIdentifier(OmniStr)
        }

        return nil
    }

    func pumpManagerFromRawValue(_ rawValue: [String: Any]) -> PumpManagerUI? {
        guard let rawState = rawValue["state"] as? PumpManager.RawStateValue,
            let Manager = pumpManagerTypeFromRawValue(rawValue)
            else {
                return nil
        }

        return Manager.init(rawState: rawState) as? PumpManagerUI
    }
    
    private func checkPumpDataAndLoop() async {
        guard !crashRecoveryManager.pendingCrashRecovery else {
            self.log.default("Loop paused pending crash recovery acknowledgement.")
            return
        }

        self.log.default("Asserting current pump data")
        guard let pumpManager = pumpManager else {
            // Run loop, even if pump is missing, to ensure stored dosing decision
            await self.loopControl.loop()
            return
        }

        let _ = await pumpManager.ensureCurrentPumpData()
        await self.loopControl.loop()
    }


    /// An active high temp basal (greater than the basal schedule) is cancelled when the CGM data is unreliable.
    private func receivedUnreliableCGMReading() async {
        guard case .tempBasal(let tempBasal) = pumpManager?.status.basalDeliveryState else {
            return
        }

        guard let scheduledBasalRate = settingsManager.settings.basalRateSchedule?.value(at: tempBasal.startDate),
              tempBasal.unitsPerHour > scheduledBasalRate else
        {
            return
        }

        // Cancel active high temp basal
        try? await loopControl.cancelActiveTempBasal(for: .unreliableCGMData)
    }

    private func processCGMReadingResult(_ manager: CGMManager, readingResult: CGMReadingResult) async -> Bool {
        var storedNewGlucose = false
        switch readingResult {
        case .newData(let values):
            do {
                let storedSamples = try await glucoseStore.addGlucoseSamples(values)
                storedNewGlucose = !storedSamples.isEmpty
                analyticsServicesManager.didStoreGlucose(storedSamples)
            } catch {
                log.error("Unable to store glucose: %{public}@", String(describing: error))
            }
            if !values.isEmpty {
                self.cgmStalenessMonitor.cgmGlucoseSamplesAvailable(values)
                // GlucoseAlertManager owns the decision based on the
                // active CGM's providesOwnGlucoseAlerts flag and the
                // user's override; we just hand it the samples.
                await self.glucoseAlertManager.evaluate(samples: values)
            }
        case .unreliableData:
            await self.receivedUnreliableCGMReading()
        case .noData:
            break
        case .error(let error):
            self.setLastError(error: error)
        }
        updatePumpManagerBLEHeartbeatPreference()
        return storedNewGlucose
    }

    var availableCGMManagers: [CGMManagerDescriptor] {
        var availableCGMManagers = pluginManager.availableCGMManagers + availableStaticCGMManagers
        if let pumpManagerAsCGMManager = pumpManager as? CGMManager {
            let identifier = pumpManagerAsCGMManager.pluginIdentifier
            let manufacturer = pluginManager.pluginBundle(forIdentifier: identifier)?.object(forInfoDictionaryKey: LoopPluginBundleKey.deviceManufacturer.rawValue) as? String
            availableCGMManagers.append(
                CGMManagerDescriptor(
                    identifier: identifier,
                    localizedTitle: pumpManagerAsCGMManager.localizedTitle,
                    manufacturer: manufacturer,
                    image: (type(of: pumpManagerAsCGMManager) as? CGMManagerUI.Type)?.pickerImage
                )
            )
        }
        
        availableCGMManagers = availableCGMManagers.filter({ cgmManager in
            guard !deviceWhitelist.cgmDevices.isEmpty else {
                return true
            }
            
            return deviceWhitelist.cgmDevices.contains(cgmManager.identifier)
        })

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

        let result = cgmManagerUIType.setupViewController(bluetoothProvider: bluetoothProvider, displayGlucosePreference: displayGlucosePreference, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures, prefersToSkipUserInteraction: prefersToSkipUserInteraction)
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
        guard identifier == pumpManager?.pluginIdentifier, let cgmManager = pumpManager as? CGMManager else {
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
            Task {
                await self.deliveryUncertaintyAlertManager?.showAlert()
            }
        }
    }

    func getHealthStoreAuthorization(_ completion: @escaping (HKAuthorizationRequestStatus) -> Void) {
        healthStore.getRequestStatusForAuthorization(toShare: shareTypes, read: readTypes) { (authorizationRequestStatus, _) in
            completion(authorizationRequestStatus)
        }
    }

    /// The sharing (write) authorization status for a HealthKit type.
    ///
    /// HealthKit only exposes share/write authorization. Read authorization is
    /// intentionally hidden by the system for privacy, so there is no equivalent
    /// accessor for read access.
    func healthKitSharingStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        healthStore.authorizationStatus(for: type)
    }
    
    // Get HealthKit authorization for all of the stores
    func authorizeHealthStore(_ completion: @escaping (HKAuthorizationRequestStatus) -> Void) {
        // Authorize all types at once for simplicity
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { (success, error) in
            Task { @MainActor in
                if success {
                    // Call the individual authorization methods to trigger query creation
                    self.carbStore.hkSampleStore?.authorizationIsDetermined()
                    self.doseStore.hkSampleStore?.authorizationIsDetermined()
                    self.glucoseStore.hkSampleStore?.authorizationIsDetermined()
                }
                self.getHealthStoreAuthorization(completion)
            }
        }
    }

    private func refreshCGM() async {
        guard let cgmManager = cgmManager else {
            return
        }

        let result = await cgmManager.fetchNewDataIfNeeded()

        let storedNewGlucose = await self.processCGMReadingResult(cgmManager, readingResult: result)

        // A heartbeat/refresh triggers a CGM check; only loop if that check produced a new value
        // AND we haven't looped in the last 4.2 min. Both conditions matter:
        //  - Requiring a new value stops the heartbeat dosing on a stale reading when it fires
        //    between CGM readings (and, via the store's syncID dedup, stops the push path and this
        //    path both firing on the same reading — whichever stores it first loops).
        //  - Keeping the interval floor stops a fast CGM (or the irregular ~2 min heartbeat) from
        //    looping more often than once per ~5 min, matching the push path's rate limit.
        let lastLoopCompleted = self.loopControl.lastLoopCompleted
        if storedNewGlucose, lastLoopCompleted == nil || lastLoopCompleted!.timeIntervalSinceNow < -.minutes(4.2) {
            self.log.default("Triggering Loop from refreshCGM() — new glucose stored")
            await self.checkPumpDataAndLoop()
        }
    }

    func refreshDeviceData() async {
        await refreshCGM()

        guard let pumpManager = self.pumpManager, pumpManager.isOnboarded else {
            return
        }

        await pumpManager.ensureCurrentPumpData()
    }

    var isGlucoseValueStale: Bool {
        guard let latestGlucoseDataDate = glucoseStore.latestGlucose?.startDate else { return true }

        return Date().timeIntervalSince(latestGlucoseDataDate) > LoopCoreConstants.inputDataRecencyInterval
    }
}

private extension DeviceDataManager {
    func setupCGM() {
        cgmManager?.cgmManagerDelegate = self
        cgmManager?.delegateQueue = DispatchQueue.main
        reportPluginInitializationComplete()

        glucoseStore.managedDataInterval = cgmManager?.managedDataInterval
        glucoseStore.healthKitStorageDelay = cgmManager.map{ type(of: $0).healthKitStorageDelay } ?? 0

        updatePumpManagerBLEHeartbeatPreference()
        if let cgmManager = cgmManager {
            alertManager?.addAlertResponder(managerIdentifier: cgmManager.pluginIdentifier,
                                            alertResponder: cgmManager)
            alertManager?.addAlertSoundVendor(managerIdentifier: cgmManager.pluginIdentifier,
                                              soundVendor: cgmManager)
            cgmHasValidSensorSession = cgmManager.cgmManagerStatus.hasValidSensorSession

            analyticsServicesManager.identifyCGMType(cgmManager.pluginIdentifier)
            cgmDeviceModel = cgmManager.cgmManagerStatus.device?.model
            analyticsServicesManager.identifyCGMModel(cgmDeviceModel)
        }
        // Refresh the GlucoseAlertManager's view of whether the active
        // CGM does its own alerting. No active CGM ⇒ treat as "no
        // native alerts" so Loop alerts stay on.
        glucoseAlertManager.cgmProvidesOwnAlerts = cgmManager?.providesOwnGlucoseAlerts ?? false

        if let cgmManagerUI = cgmManager as? CGMManagerUI {
            displayGlucoseUnitBroadcaster?.addDisplayGlucoseUnitObserver(cgmManagerUI)
        }
    }

    func setupPump() {
        dispatchPrecondition(condition: .onQueue(.main))

        pumpManager?.pumpManagerDelegate = self
        reportPluginInitializationComplete()

        doseStore.device = pumpManager?.status.device
        pumpManagerHUDProvider = (pumpManager as? PumpManagerUI)?.hudProvider(bluetoothProvider: bluetoothProvider, colorPalette: .default, allowedInsulinTypes: allowedInsulinTypes)

        // Proliferate PumpModel preferences to DoseStore
        if let pumpRecordsBasalProfileStartEvents = pumpManager?.pumpRecordsBasalProfileStartEvents {
            doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
        }
        if let pumpManager = pumpManager as? PumpManagerUI {
            alertManager?.addAlertResponder(managerIdentifier: pumpManager.pluginIdentifier,
                                                  alertResponder: pumpManager)
            alertManager?.addAlertSoundVendor(managerIdentifier: pumpManager.pluginIdentifier,
                                                    soundVendor: pumpManager)
            
            deliveryUncertaintyAlertManager = DeliveryUncertaintyAlertManager(pumpManager: pumpManager, alertPresenter: alertPresenter)

            analyticsServicesManager.identifyPumpType(pumpManager.pluginIdentifier)
            analyticsServicesManager.identifyPumpModel(pumpManager.status.device.model)

            updatePumpManagerBLEHeartbeatPreference()
        }
    }

    func setLastError(error: Error) {
        DispatchQueue.main.async {
            self.lastError = (date: Date(), error: error)
        }
    }
}

// MARK: - Plugins
extension DeviceDataManager {
    func reportPluginInitializationComplete() {
        let allActivePlugins = self.allActivePlugins
        
        for plugin in activeServicesProvider.activeServices {
            plugin.initializationComplete(for: allActivePlugins)
        }
        
        for plugin in activeStatefulPluginsProvider.activeStatefulPlugins {
            plugin.initializationComplete(for: allActivePlugins)
        }
        
        for plugin in availableSupports {
            plugin.initializationComplete(for: allActivePlugins)
        }
        
        cgmManager?.initializationComplete(for: allActivePlugins)
        pumpManager?.initializationComplete(for: allActivePlugins)
    }
    
    var allActivePlugins: [Pluggable] {
        var allActivePlugins: [Pluggable] = activeServicesProvider.activeServices
        
        for plugin in activeStatefulPluginsProvider.activeStatefulPlugins {
            if !allActivePlugins.contains(where: { $0.pluginIdentifier == plugin.pluginIdentifier }) {
                allActivePlugins.append(plugin)
            }
        }
        
        for plugin in availableSupports {
            if !allActivePlugins.contains(where: { $0.pluginIdentifier == plugin.pluginIdentifier }) {
                allActivePlugins.append(plugin)
            }
        }
        
        if let cgmManager = cgmManager {
            if !allActivePlugins.contains(where: { $0.pluginIdentifier == cgmManager.pluginIdentifier }) {
                allActivePlugins.append(cgmManager)
            }
        }
        
        if let pumpManager = pumpManager {
            if !allActivePlugins.contains(where: { $0.pluginIdentifier == pumpManager.pluginIdentifier }) {
                allActivePlugins.append(pumpManager)
            }
        }
        
        return allActivePlugins
    }
}

// MARK: - Client API
extension DeviceDataManager {
    func enactBolus(units: Double, decisionId: UUID?, activationType: BolusActivationType) async throws {
        guard let pumpManager = pumpManager else {
            throw LoopError.configurationError(.pumpManager)
        }

        var automaticBolusOngoing = false
        if case .inProgress(let dose) = pumpManager.status.bolusState, dose.automatic == true {
            automaticBolusOngoing = true
        }

        if automaticBolusOngoing && activationType != .automatic {
            let _ = try? await pumpManager.cancelBolus()
        }

        do {
            try await pumpManager.enactBolus(decisionId: decisionId, units: units, activationType: activationType)
        } catch PumpManagerError.uncertainDelivery {
            // Do not generate notification on uncertain delivery error
        } catch {
            if !activationType.isAutomatic, let error = error as? PumpManagerError {
                do {
                    try await NotificationManager.sendBolusFailureNotification(for: error, units: units, at: Date(), decisionId: decisionId, activationType: activationType)
                } catch {
                    log.error("Error sending bolus failure notification %{public}@", String(describing: error))
                }
            }
        }
    }

    func glucoseDisplay(for glucose: GlucoseSampleValue?) -> GlucoseDisplayable? {
        guard let glucose = glucose else {
            return cgmManager?.glucoseDisplay
        }
        
        guard FeatureFlags.cgmManagerCategorizeManualGlucoseRangeEnabled else {
            // Using Dexcom default glucose thresholds to categorize a glucose range
            let urgentLowGlucoseThreshold = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 55)
            let lowGlucoseThreshold = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 80)
            let highGlucoseThreshold = LoopQuantity(unit: .milligramsPerDeciliter, doubleValue: 200)
            
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
        Task {
            await runDueScheduledProfileSwitch()
        }
    }

    func updatePumpManagerBLEHeartbeatPreference() {
        guard pumpManagerMustProvideBLEHeartbeat else {
            pumpManager?.setBLEHeartbeatRequest(nil)
            return
        }
        // Tell the pump when the last CGM reading landed and how often readings are expected, so it can
        // schedule its next heartbeat to arrive just after the next reading is due (the pump adds its own
        // buffer for the remote CGM value to be fetched and stored).
        let request = PumpHeartbeatRequest(
            lastCGMReadingDate: glucoseStore.latestGlucose?.startDate,
            expectedCGMReadingInterval: cgmManager?.expectedGlucoseSampleInterval ?? .minutes(5))
        pumpManager?.setBLEHeartbeatRequest(request)
    }
}

// MARK: - DeviceManagerDelegate
extension DeviceDataManager: DeviceManagerDelegate {

    nonisolated func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?, type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {
        Task { @MainActor in
            deviceLog.log(managerIdentifier: manager.pluginIdentifier, deviceIdentifier: deviceIdentifier, type: type, message: message, completion: completion)
        }
    }

    func deviceManager(_ manager: DeviceManager, recordAnalyticsEvent name: String, properties: [AnyHashable: Any]?) {
        analyticsServicesManager.deviceManagerDidRecordEvent(name, properties: properties)
    }

    var allowDebugFeatures: Bool {
        FeatureFlags.allowDebugFeatures // NOTE: DEBUG FEATURES - DEBUG AND TEST ONLY
    }
}

// MARK: - AlertIssuer
extension DeviceDataManager: AlertIssuer {
    static let managerIdentifier = "DeviceDataManager"

    func issueAlert(_ alert: Alert) async {
        await alertManager?.issueAlert(alert)
    }

    func retractAlert(identifier: Alert.Identifier) async {
        await alertManager?.retractAlert(identifier: identifier)
    }
}

// MARK: - PersistedAlertStore
extension DeviceDataManager: PersistedAlertStore {
    func doesIssuedAlertExist(identifier: LoopKit.Alert.Identifier) async throws -> Bool {
        precondition(alertManager != nil)
        return try await alertManager.doesIssuedAlertExist(identifier: identifier)
    }
    
    func lookupAllUnretracted(managerIdentifier: String) async throws -> [LoopKit.PersistedAlert] {
        precondition(alertManager != nil)
        return try await alertManager.lookupAllUnretracted(managerIdentifier: managerIdentifier)
    }
    
    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String) async throws -> [LoopKit.PersistedAlert] {
        precondition(alertManager != nil)
        return try await alertManager.lookupAllUnacknowledgedUnretracted(managerIdentifier: managerIdentifier)
    }

    func recordRetractedAlert(_ alert: Alert, at date: Date) async throws {
        precondition(alertManager != nil)
        try await alertManager.recordRetractedAlert(alert, at: date)
    }
}

// MARK: - CGMManagerDelegate
extension DeviceDataManager: CGMManagerDelegate {
    func cgmManagerWantsDeletion(_ manager: CGMManager) async {
        log.default("CGM manager with identifier '%{public}@' wants deletion", manager.pluginIdentifier)
        if let cgmManagerUI = cgmManager as? CGMManagerUI {
            displayGlucoseUnitBroadcaster?.removeDisplayGlucoseUnitObserver(cgmManagerUI)
        }
        cgmManager = nil
        settingsManager.storeSettings()
    }

    nonisolated
    func cgmManager(_ manager: CGMManager, hasNew readingResult: CGMReadingResult) {
        Task { @MainActor in
            log.default("CGMManager:%{public}@ did update with %{public}@", String(describing: type(of: manager)), String(describing: readingResult))
            let storedNewGlucose = await processCGMReadingResult(manager, readingResult: readingResult)
            let now = Date()
            // A CGM can re-deliver readings the store already holds (Nightscout polls do, every
            // poll). Only a reading that was actually stored is a reason to run the loop.
            if storedNewGlucose, now.timeIntervalSince(self.lastCGMLoopTrigger) > .minutes(4.2) {
                self.log.default("Triggering loop from new CGM data at %{public}@", String(describing: now))
                self.lastCGMLoopTrigger = now
                await self.checkPumpDataAndLoop()
            }
        }
    }

    nonisolated
    func cgmManager(_ manager: LoopKit.CGMManager, hasNew events: [PersistedCgmEvent]) {
        Task { @MainActor in
            do {
                try await cgmEventStore.add(events: events)
            } catch {
                self.log.error("Error storing cgm events: %{public}@", error.localizedDescription)
            }
        }
    }

    func startDateToFilterNewData(for manager: CGMManager) -> Date? {
        dispatchPrecondition(condition: .onQueue(.main))
        return glucoseStore.latestGlucose?.startDate
    }

    func cgmManagerDidUpdateState(_ manager: CGMManager) {
        dispatchPrecondition(condition: .onQueue(.main))
        rawCGMManager = manager.rawValue
    }

    func credentialStoragePrefix(for manager: CGMManager) -> String {
        // return string unique to this instance of the CGMManager
        return UUID().uuidString
    }

    nonisolated func supportsWatchDirectRead(for manager: CGMManager) -> Bool {
        true
    }

    nonisolated
    func cgmManager(_ manager: CGMManager, didUpdate status: CGMManagerStatus) {
        DispatchQueue.main.async {
            if self.cgmHasValidSensorSession != status.hasValidSensorSession {
                self.cgmHasValidSensorSession = status.hasValidSensorSession
            }
            if self.cgmDeviceModel != status.device?.model {
                self.cgmDeviceModel = status.device?.model
                self.analyticsServicesManager.identifyCGMModel(self.cgmDeviceModel)
            }
            self.glucoseStore.managedDataInterval = manager.managedDataInterval
        }
    }
}

// MARK: - CGMManagerOnboardingDelegate

extension DeviceDataManager: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager cgmManager: CGMManagerUI) {
        log.default("CGM manager with identifier '%{public}@' created", cgmManager.pluginIdentifier)
        self.cgmManager = cgmManager
    }

    func cgmManagerOnboarding(didOnboardCGMManager cgmManager: CGMManagerUI) {
        precondition(cgmManager.isOnboarded)
        log.default("CGM manager with identifier '%{public}@' onboarded", cgmManager.pluginIdentifier)

        Task { @MainActor in
            await refreshDeviceData()
            settingsManager.storeSettings()
        }
    }
}

// MARK: - PumpManagerDelegate
extension DeviceDataManager: PumpManagerDelegate {
    var automatedTreatmentState: LoopKit.AutomatedTreatmentState? {
        return loopControl.automatedTreatmentState
    }
    
    var detectedSystemTimeOffset: TimeInterval { UserDefaults.standard.detectedSystemTimeOffset ?? 0 }

    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(.main))
        log.default("PumpManager:%{public}@ did adjust pump clock by %fs", String(describing: type(of: pumpManager)), adjustment)

        analyticsServicesManager.pumpTimeDidDrift(adjustment)
    }

    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {
        dispatchPrecondition(condition: .onQueue(.main))
        log.default("PumpManager:%{public}@ did update state", String(describing: type(of: pumpManager)))

        rawPumpManager = pumpManager.rawValue
    }
    
    func pumpManager(_ pumpManager: PumpManager, didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule, completion: @escaping (Error?) -> Void) {
        saveUpdatedBasalRateSchedule(basalRateSchedule)
        completion(nil)
    }

    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {
        Task { @MainActor in
            log.default("PumpManager:%{public}@ did fire heartbeat", String(describing: type(of: pumpManager)))
            await refreshCGM()
        }
    }

    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        return pumpManagerMustProvideBLEHeartbeat
    }

    private var pumpManagerMustProvideBLEHeartbeat: Bool {
        /// Controls the management of the RileyLink timer tick, which is a reliably-changing BLE
        /// characteristic which can cause the app to wake. For most users, the G5 Transmitter and
        /// G4 Receiver are reliable as hearbeats, but users who find their resources extremely constrained
        /// due to greedy apps or older devices may choose to always enable the timer by always setting `true`
        return !(cgmManager?.providesBLEHeartbeat == true)
    }

    nonisolated func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {
        Task { @MainActor in
            log.default("PumpManager:%{public}@ did update status: %{public}@", String(describing: type(of: pumpManager)), String(describing: status))

            doseStore.device = status.device

            if status.device.model != oldStatus.device.model {
                analyticsServicesManager.identifyPumpModel(status.device.model)
            }

            if let newBatteryValue = status.pumpBatteryChargeRemaining,
               let oldBatteryValue = oldStatus.pumpBatteryChargeRemaining,
               newBatteryValue - oldBatteryValue >= LoopConstants.batteryReplacementDetectionThreshold {
                analyticsServicesManager.pumpBatteryWasReplaced()
            }

            updatePumpIsAllowingAutomation(status: status)

            // Update the pump-schedule based settings
            settingsManager.setScheduleTimeZone(status.timeZone)

            if status.deliveryIsUncertain != oldStatus.deliveryIsUncertain {
                if status.deliveryIsUncertain {
                    await self.deliveryUncertaintyAlertManager?.showAlert()
                } else {
                    self.deliveryUncertaintyAlertManager?.clearAlert()
                }
            }

            // A scheduled switch waits for a bolus to finish and for delivery to resume.
            if !status.holdsScheduledProfileSwitch, oldStatus.holdsScheduledProfileSwitch {
                await runDueScheduledProfileSwitch()
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

    nonisolated func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) {
    }
    
    func pumpManagerWantsDeletion(_ pumpManager: PumpManager) async {
        log.default("Pump manager with identifier '%{public}@' wants deletion", pumpManager.pluginIdentifier)

        self.pumpManager = nil
        deliveryUncertaintyAlertManager = nil
        settingsManager.storeSettings()
    }

    nonisolated func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {
        Task { @MainActor in
            log.default("PumpManager:%{public}@ did update pumpRecordsBasalProfileStartEvents to %{public}@", String(describing: type(of: pumpManager)), String(describing: pumpRecordsBasalProfileStartEvents))
            doseStore.pumpRecordsBasalProfileStartEvents = pumpRecordsBasalProfileStartEvents
        }
    }

    nonisolated func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {
        Task { @MainActor in
            dispatchPrecondition(condition: .onQueue(.main))
            log.error("PumpManager:%{public}@ did error: %{public}@", String(describing: type(of: pumpManager)), String(describing: error))

            setLastError(error: error)
        }
    }

    nonisolated func pumpManager(
        _ pumpManager: PumpManager,
        hasNewPumpEvents events: [NewPumpEvent],
        lastReconciliation: Date?,
        replacePendingEvents: Bool,
        completion: @escaping (_ error: Error?) -> Void)
    {
        Task { @MainActor in
            log.default("PumpManager:%{public}@ hasNewPumpEvents (lastReconciliation = %{public}@)", String(describing: type(of: pumpManager)), String(describing: lastReconciliation))
            do {
                try await doseStore.addPumpEvents(events, lastReconciliation: lastReconciliation, replacePendingEvents: replacePendingEvents)
            } catch {
                self.log.error("Failed to addPumpEvents to DoseStore: %{public}@", String(describing: error))
                completion(error)
                return
            }
            completion(nil)
            NotificationCenter.default.post(name: .PumpEventsAdded, object: self, userInfo: nil)
        }
    }

    nonisolated func pumpManager(
        _ pumpManager: PumpManager,
        didReadReservoirValue units: Double,
        at date: Date,
        completion: @escaping (_ result: Swift.Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void
    ) {
        Task { @MainActor in
            dispatchPrecondition(condition: .onQueue(.main))
            log.default("PumpManager:%{public}@ did read reservoir value", String(describing: type(of: pumpManager)))

            do {
                let (newValue, lastValue, areStoredValuesContinuous) = try await doseStore.addReservoirValue(units, at: date)
                completion(.success((newValue: newValue, lastValue: lastValue, areStoredValuesContinuous: areStoredValuesContinuous)))
            } catch {
                self.log.error("Failed to addReservoirValue: %{public}@", String(describing: error))
                completion(.failure(error))
            }
        }
    }

    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date {
        return doseStore.pumpEventQueryAfterDate
    }

    var automaticDosingEnabled: Bool {
        settingsManager.dosingEnabled
    }
}

// MARK: - PumpManagerOnboardingDelegate

extension DeviceDataManager: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        log.default("Pump manager with identifier '%{public}@' created", pumpManager.pluginIdentifier)
        self.pumpManager = pumpManager
    }

    func pumpManagerOnboarding(didOnboardPumpManager pumpManager: PumpManagerUI) {
        precondition(pumpManager.isOnboarded)
        log.default("Pump manager with identifier '%{public}@' onboarded", pumpManager.pluginIdentifier)

        Task {
            await refreshDeviceData()
            settingsManager.storeSettings()
        }
    }

    func pumpManagerOnboarding(didPauseOnboarding pumpManager: PumpManagerUI) {
        
    }
}

// MARK: - AlertStoreDelegate
extension DeviceDataManager: AlertStoreDelegate {
    func alertStoreHasUpdatedAlertData(_ alertStore: AlertStore) {
        uploadEventListener.triggerUpload(for: .alert)
    }
}

// MARK: - CarbStoreDelegate
extension DeviceDataManager: CarbStoreDelegate {
    func carbStoreHasUpdatedCarbData(_ carbStore: CarbStore) {
        uploadEventListener.triggerUpload(for: .carb)
    }

    func carbStore(_ carbStore: CarbStore, didError error: CarbStore.CarbStoreError) {}
}

// MARK: - DoseStoreDelegate
extension DeviceDataManager: DoseStoreDelegate {
    func scheduledBasalHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Double>] {
        try await settingsManager.getBasalHistory(startDate: start, endDate: end)
    }
    
    func doseStoreHasUpdatedPumpEventData(_ doseStore: DoseStore) {
        uploadEventListener.triggerUpload(for: .pumpEvent)
    }
}

// MARK: - DosingDecisionStoreDelegate
extension DeviceDataManager: DosingDecisionStoreDelegate {
    func dosingDecisionStoreHasUpdatedDosingDecisionData(_ dosingDecisionStore: DosingDecisionStore) {
        uploadEventListener.triggerUpload(for: .dosingDecision)
    }
}

// MARK: - GlucoseStoreDelegate
extension DeviceDataManager: GlucoseStoreDelegate {
    func glucoseStoreHasUpdatedGlucoseData(_ glucoseStore: GlucoseStore) {
        uploadEventListener.triggerUpload(for: .glucose)
    }
}

// MARK: - InsulinDeliveryStoreDelegate
extension DeviceDataManager: InsulinDeliveryStoreDelegate {
    func insulinDeliveryStoreHasUpdatedDoseData(_ insulinDeliveryStore: InsulinDeliveryStore) {
        uploadEventListener.triggerUpload(for: .dose)
    }
}

// MARK: - CgmEventStoreDelegate
extension DeviceDataManager: CgmEventStoreDelegate {
    func cgmEventStoreHasUpdatedData(_ cgmEventStore: LoopKit.CgmEventStore) {
        uploadEventListener.triggerUpload(for: .cgmEvent)
    }
}


// MARK: - TestingPumpManager
extension DeviceDataManager {
    func deleteTestingPumpData() async throws {
        guard let testingPumpManager = pumpManager as? TestingPumpManager else {
            return
        }

        let insulinDeliveryStore = doseStore.insulinDeliveryStore

        try await doseStore.resetPumpData()

        let insulinSharingDenied = self.healthStore.authorizationStatus(for: HealthKitSampleStore.insulinQuantityType) == .sharingDenied
        guard !insulinSharingDenied else {
            // only clear cache since access to health kit is denied
            await insulinDeliveryStore.purgeCachedInsulinDeliveryObjects()
            return
        }

        try await insulinDeliveryStore.purgeDoseEntriesForDevice(testingPumpManager.testingDevice)
    }

    func deleteTestingCGMData() async throws {
        guard let testingCGMManager = cgmManager as? TestingCGMManager else {
            return
        }

        let glucoseSharingDenied = self.healthStore.authorizationStatus(for: HealthKitSampleStore.glucoseType) == .sharingDenied
        guard !glucoseSharingDenied else {
            // only clear cache since access to health kit is denied
            try await glucoseStore.purgeCachedGlucoseObjects()
            return
        }

        try await glucoseStore.purgeAllGlucose(for: testingCGMManager.testingDevice)
    }
    
    func deleteTestingCarbData(before: Date = Date()) async throws {
        guard cgmManager is TestingCGMManager, pumpManager is TestingPumpManager else {
            return
        }
        
        try await carbStore.deleteAllCarbEntries()
    }
    
    func deleteTestingAlertData() async throws {
        guard cgmManager is TestingCGMManager, pumpManager is TestingPumpManager else {
            return
        }
        
        await withCheckedContinuation { [weak alertStore = alertManager.alertStore] continuation in
            alertStore?.purge(before: Date(), completion: { _ in
                continuation.resume()
            })
        }
    }
}

extension DeviceDataManager: BolusDurationEstimator {
    func estimateBolusDuration(bolusUnits: Double) -> TimeInterval? {
        pumpManager?.estimatedDuration(toBolus: bolusUnits)
    }
}

extension Notification.Name {
    static let PumpManagerChanged = Notification.Name(rawValue:  "com.loopKit.notification.PumpManagerChanged")
    static let CGMManagerChanged = Notification.Name(rawValue:  "com.loopKit.notification.CGMManagerChanged")
    static let PumpEventsAdded = Notification.Name(rawValue:  "com.loopKit.notification.PumpEventsAdded")
}

//MARK: - CGMStalenessMonitorDelegate protocol conformance

extension GlucoseStore : CGMStalenessMonitorDelegate { }


//MARK: TherapySettingsViewModelDelegate
struct CancelTempBasalFailedMaximumBasalRateChangedError: LocalizedError {
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
    var shouldSyncGlucoseToRemoteService: Bool {
        guard let cgmManager = cgmManager else {
            return true
        }
        return cgmManager.shouldSyncToRemoteService
    }
}

extension DeviceDataManager: TherapySettingsViewModelDelegate {
    
    /// Profile changes are refused while the basal schedule is written, so the pump and the settings end up with
    /// the same schedule. A suspended pump would resume delivery when it takes a basal schedule, so the schedule is
    /// not sent.
    func syncBasalRateSchedule(items: [RepeatingScheduleValue<Double>], completion: @escaping (Swift.Result<BasalRateSchedule, Error>) -> Void) {
        guard let pumpManager else {
            return
        }
        guard !therapyProfileChangeInProgress else {
            completion(.failure(TherapyProfileError.operationInProgress))
            return
        }
        switch pumpManager.status.basalDeliveryState {
        case .suspended, .suspending:
            completion(.failure(TherapyProfileError.pumpSuspended))
            return
        default:
            break
        }
        therapyProfileChangeInProgress = true
        pumpManager.syncBasalRateSchedule(items: items) { result in
            Task { @MainActor in
                self.therapyProfileChangeInProgress = false
                completion(result)
            }
        }
    }
    
    func syncDeliveryLimits(deliveryLimits: DeliveryLimits) async throws -> DeliveryLimits
    {
        // FIRST we need to check to make sure if we have to cancel temp basal first
        if let maxRate = deliveryLimits.maximumBasalRate?.doubleValue(for: .internationalUnitsPerHour),
           case .tempBasal(let dose) = basalDeliveryState,
           dose.unitsPerHour > maxRate
        {
            // Temp basal is higher than proposed rate, so should cancel
            try await self.loopControl.cancelActiveTempBasal(for: .maximumBasalRateChanged)
        }
        
        return try await pumpManager?.syncDeliveryLimits(limits: deliveryLimits) ?? deliveryLimits
    }

    /// Edits must start from the active profile's current schedules, and no profile change may be running.
    func validateTherapySettingsEdit(from therapySettings: TherapySettings) throws {
        guard !therapyProfileChangeInProgress else {
            throw TherapyProfileError.operationInProgress
        }
        let activeName = activeTherapyProfileName
        guard TherapyProfiles.activeName(therapySettings.activeProfileName) == activeName else {
            throw TherapyProfileError.activeProfileChangedWhileEditing(activeName)
        }
        let edited = TherapyProfile(name: activeName,
                                    glucoseTargetRangeSchedule: therapySettings.glucoseTargetRangeSchedule,
                                    carbRatioSchedule: therapySettings.carbRatioSchedule,
                                    basalRateSchedule: therapySettings.basalRateSchedule,
                                    insulinSensitivitySchedule: therapySettings.insulinSensitivitySchedule)
        let live = settingsManager.loopSettings.liveTherapyProfile
        if let edited, let live {
            guard edited.hasSameValues(as: live) else {
                throw TherapyProfileError.settingsChangedWhileEditing
            }
        } else if (edited == nil) != (live == nil) {
            throw TherapyProfileError.settingsChangedWhileEditing
        }
    }

    /// Settings for another profile than the active one, or saved while a profile change runs, are not saved, so
    /// stale schedules never reach the active profile.
    func saveCompletion(therapySettings: TherapySettings) {
        guard !therapyProfileChangeInProgress else {
            log.error("Therapy settings not saved: a profile change is in progress")
            return
        }
        guard TherapyProfiles.activeName(therapySettings.activeProfileName) == activeTherapyProfileName else {
            log.error("Therapy settings for profile %{public}@ not saved: %{public}@ is active", TherapyProfiles.activeName(therapySettings.activeProfileName), activeTherapyProfileName)
            return
        }
        settingsManager.mutateLoopSettings { settings in
            settings.glucoseTargetRangeSchedule = therapySettings.glucoseTargetRangeSchedule
            settings.preMealTargetRange = therapySettings.correctionRangeOverrides?.preMeal
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

extension DeviceDataManager: TherapyProfileDelegate {

    var therapyProfiles: [TherapyProfile] {
        settingsManager.loopSettings.resolvedTherapyProfiles
    }

    var activeTherapyProfileName: String {
        TherapyProfiles.activeName(settingsManager.loopSettings.activeProfileName)
    }

    var therapyProfileValidator: TherapyProfileValidator? {
        guard let pumpManager else {
            return nil
        }
        let settings = settingsManager.loopSettings
        return TherapyProfileValidator(supportedBasalRates: pumpManager.supportedBasalRates,
                                       maximumBasalRatePerHour: settings.maximumBasalRatePerHour,
                                       maximumBasalScheduleEntryCount: pumpManager.maximumBasalScheduleEntryCount,
                                       suspendThreshold: settings.suspendThreshold)
    }

    func activateTherapyProfile(named name: String, expectedFingerprint: String?, trigger: TherapyProfileSwitchTrigger) async throws {
        let now = Date()
        try await loggingFailure("Activating therapy profile \(name) (\(trigger.rawValue))") {
            try await self.activateTherapyProfile(named: name, expectedFingerprint: expectedFingerprint, trigger: trigger, at: now)
        }
        await armScheduledProfileSwitchAlert(now: now)
    }

    /// Validates, writes the basal schedule to the pump, then sets the four schedules, the active name and the trigger
    /// in one change. Scheduled starts up to `date`, the time of the switch, are settled in the same change.
    private func activateTherapyProfile(named name: String, expectedFingerprint: String?, trigger: TherapyProfileSwitchTrigger, at date: Date) async throws {
        try beginTherapyProfileChange()
        defer { therapyProfileChangeInProgress = false }

        guard let profile = therapyProfile(named: name) else {
            throw TherapyProfileError.notFound(name)
        }
        try checkFingerprint(of: profile, expected: expectedFingerprint)
        guard let validator = therapyProfileValidator else {
            throw TherapyProfileError.noPump
        }
        let validated = try validator.validate(profile)

        if name == activeTherapyProfileName, let live = settingsManager.loopSettings.liveTherapyProfile, live.hasSameValues(as: validated) {
            return
        }

        let syncedBasal = try await syncBasalRateSchedule(items: validated.basalRateSchedule.items)
        let live = settingsManager.loopSettings.liveTherapyProfile
        settingsManager.mutateLoopSettings { settings in
            settings.therapyProfiles = TherapyProfiles.resolved(settings.therapyProfiles, live: settings.activeProfileName == nil ? live : nil)
            settings.applyTherapyProfileSchedules(validated)
            settings.basalRateSchedule = syncedBasal
            settings.activeProfileName = name == TherapyProfile.defaultName ? nil : name
            settings.activeProfileSwitchTrigger = trigger
            settings.scheduledSwitchesSettledAt = date
        }
        log.default("Activated therapy profile %{public}@ (%{public}@)", name, trigger.rawValue)
    }

    func saveTherapyProfile(_ profile: TherapyProfile, originalName: String?, expectedFingerprint: String?) async throws {
        try await loggingFailure("Saving therapy profile \(profile.name)") {
            try await self.performSaveTherapyProfile(profile, originalName: originalName, expectedFingerprint: expectedFingerprint)
        }
    }

    /// Saves `profile`; for the active profile the basal schedule goes to the pump first. Values that are already
    /// stored (a rename or a copy) are not validated again, and glucose values sent back unchanged keep their stored value.
    private func performSaveTherapyProfile(_ profile: TherapyProfile, originalName: String?, expectedFingerprint: String?) async throws {
        var profile = profile
        try beginTherapyProfileChange()
        defer { therapyProfileChangeInProgress = false }

        let isActive = originalName != nil && originalName == activeTherapyProfileName
        var original: TherapyProfile?
        if let originalName {
            guard let stored = therapyProfile(named: originalName) else {
                throw TherapyProfileError.notFound(originalName)
            }
            try checkFingerprint(of: stored, expected: expectedFingerprint)
            original = stored
            profile = profile.keepingStoredGlucoseValues(of: stored)
        }
        var validated: TherapyProfile
        let holdsStoredValues = original.map { profile.hasSameValues(as: $0) } ?? therapyProfiles.contains { profile.hasSameValues(as: $0) }
        if holdsStoredValues {
            validated = profile
        } else {
            guard let validator = therapyProfileValidator else {
                throw TherapyProfileError.noPump
            }
            validated = try validator.validate(profile)
        }
        if let timeZone = settingsManager.loopSettings.basalRateSchedule?.timeZone {
            validated = validated.withTimeZone(timeZone)
        }

        let loopSettings = settingsManager.loopSettings
        let live = loopSettings.liveTherapyProfile
        let result = try TherapyProfiles.saving(validated,
                                                originalName: originalName,
                                                in: loopSettings.therapyProfiles,
                                                activeProfileName: loopSettings.activeProfileName,
                                                live: live)

        if isActive {
            let syncedBasal: BasalRateSchedule
            if let live, live.basalRateSchedule.items == validated.basalRateSchedule.items {
                syncedBasal = live.basalRateSchedule
            } else {
                syncedBasal = try await syncBasalRateSchedule(items: validated.basalRateSchedule.items)
            }
            settingsManager.mutateLoopSettings { settings in
                settings.therapyProfiles = result.profiles
                settings.activeProfileName = result.activeProfileName
                settings.applyTherapyProfileSchedules(validated)
                settings.basalRateSchedule = syncedBasal
                if let originalName {
                    settings.scheduledSwitches = ScheduledProfileSwitches.renaming(settings.scheduledSwitches, from: originalName, to: validated.name)
                }
            }
        } else {
            settingsManager.mutateLoopSettings { settings in
                settings.therapyProfiles = result.profiles
                settings.activeProfileName = result.activeProfileName
                if let originalName {
                    settings.scheduledSwitches = ScheduledProfileSwitches.renaming(settings.scheduledSwitches, from: originalName, to: validated.name)
                }
            }
        }
        if let originalName, originalName != validated.name {
            await armScheduledProfileSwitchAlert()
        }
        log.default("Saved therapy profile %{public}@ (original %{public}@, active %{public}@)", validated.name, originalName ?? "none", String(describing: isActive))
    }

    func deleteTherapyProfile(named name: String, expectedFingerprint: String?) async throws {
        try await loggingFailure("Deleting therapy profile \(name)") {
            try await self.performDeleteTherapyProfile(named: name, expectedFingerprint: expectedFingerprint)
        }
    }

    private func performDeleteTherapyProfile(named name: String, expectedFingerprint: String?) async throws {
        try beginTherapyProfileChange()
        defer { therapyProfileChangeInProgress = false }

        let loopSettings = settingsManager.loopSettings
        let profiles = try TherapyProfiles.deleting(name, in: loopSettings.therapyProfiles, activeProfileName: loopSettings.activeProfileName, live: loopSettings.liveTherapyProfile)
        if let profile = therapyProfile(named: name) {
            try checkFingerprint(of: profile, expected: expectedFingerprint)
        }
        let removedSwitches = settingsManager.loopSettings.scheduledSwitches.filter { $0.profileName == name }.count
        settingsManager.mutateLoopSettings { settings in
            settings.therapyProfiles = profiles
            settings.scheduledSwitches = ScheduledProfileSwitches.removing(profile: name, from: settings.scheduledSwitches)
        }
        log.default("Deleted therapy profile %{public}@ and %d scheduled switches", name, removedSwitches)
        if removedSwitches > 0 {
            await armScheduledProfileSwitchAlert()
        }
    }

    var scheduledProfileSwitches: [ScheduledProfileSwitch] {
        settingsManager.loopSettings.scheduledSwitches
    }

    func saveScheduledProfileSwitches(_ entries: [ScheduledProfileSwitch], expectedFingerprint: String?) async throws {
        try await loggingFailure("Saving \(entries.count) scheduled profile switches") {
            try await self.performSaveScheduledProfileSwitches(entries, expectedFingerprint: expectedFingerprint)
        }
    }

    /// Only starts after the save run: the save settles every earlier one.
    private func performSaveScheduledProfileSwitches(_ entries: [ScheduledProfileSwitch], expectedFingerprint: String?) async throws {
        try beginTherapyProfileChange()
        defer { therapyProfileChangeInProgress = false }

        let current = settingsManager.loopSettings.scheduledSwitches
        if let expectedFingerprint, ScheduledProfileSwitches.fingerprint(current) != expectedFingerprint {
            throw ScheduledProfileSwitchError.conflict
        }
        try ScheduledProfileSwitches.validate(entries, profileNames: therapyProfiles.map(\.name))
        guard entries != current else {
            return
        }
        let now = Date()
        settingsManager.mutateLoopSettings { settings in
            settings.scheduledSwitches = entries
            settings.scheduledSwitchesSettledAt = now
        }
        log.default("Saved %d scheduled profile switches", entries.count)
        await armScheduledProfileSwitchAlert(now: now)
    }

    func reorderTherapyProfiles(names: [String]) {
        let loopSettings = settingsManager.loopSettings
        let profiles = TherapyProfiles.reordering(loopSettings.therapyProfiles, names: names, live: loopSettings.liveTherapyProfile, activeProfileName: loopSettings.activeProfileName)
        settingsManager.mutateLoopSettings { settings in
            settings.therapyProfiles = profiles
        }
    }

    private func loggingFailure(_ action: String, _ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch {
            log.error("%{public}@ failed: %{public}@", action, String(describing: error))
            throw error
        }
    }

    private func checkFingerprint(of profile: TherapyProfile, expected fingerprint: String?) throws {
        if let fingerprint, !profile.matches(fingerprint: fingerprint) {
            throw TherapyProfileError.conflict
        }
    }

    private func beginTherapyProfileChange() throws {
        guard !therapyProfileChangeInProgress else {
            throw TherapyProfileError.operationInProgress
        }
        therapyProfileChangeInProgress = true
    }

    /// A suspended pump would resume delivery when it takes a basal schedule, so the schedule is not sent.
    private func syncBasalRateSchedule(items: [RepeatingScheduleValue<Double>]) async throws -> BasalRateSchedule {
        guard let pumpManager else {
            throw TherapyProfileError.noPump
        }
        switch pumpManager.status.basalDeliveryState {
        case .suspended, .suspending:
            throw TherapyProfileError.pumpSuspended
        default:
            break
        }
        do {
            return try await withCheckedThrowingContinuation { continuation in
                pumpManager.syncBasalRateSchedule(items: items) { result in
                    continuation.resume(with: result)
                }
            }
        } catch {
            throw TherapyProfileError.pumpSyncFailed(error.localizedDescription)
        }
    }
}

// MARK: - Scheduled profile switches

extension DeviceDataManager {

    static let scheduledProfileSwitchManagerIdentifier = "ScheduledProfileSwitches"
    /// A start is applied at most this late; an older one is reported as missed.
    static let scheduledProfileSwitchGrace = TimeInterval(hours: 24)
    /// A start not applied this long after its time raises an alert.
    static let scheduledProfileSwitchLateAlertDelay = TimeInterval(minutes: 30)

    private var scheduleTimeZone: TimeZone {
        settingsManager.loopSettings.basalRateSchedule?.timeZone ?? .current
    }

    private var pendingScheduledProfileSwitchAlertIdentifier: Alert.Identifier {
        Alert.Identifier(managerIdentifier: Self.scheduledProfileSwitchManagerIdentifier, alertIdentifier: "pending")
    }

    /// The next start that makes another profile than the active one active.
    func nextScheduledProfileSwitch(after date: Date) -> ScheduledProfileSwitchOccurrence? {
        let settings = settingsManager.loopSettings
        let activeName = TherapyProfiles.activeName(settings.activeProfileName)
        return ScheduledProfileSwitches.next(in: settings.scheduledSwitches.filter { $0.profileName != activeName }, after: date, timeZone: scheduleTimeZone)
    }

    /// Runs the newest start since the settled instant: a start older than the grace is reported as missed, a start
    /// whose profile is already active is settled, and other starts switch through the validated switch. A pump that
    /// can not take the basal schedule now leaves the start unsettled, so the next run tries again.
    func runDueScheduledProfileSwitch(now: Date = Date()) async {
        let settings = settingsManager.loopSettings
        guard !settings.scheduledSwitches.isEmpty, !therapyProfileChangeInProgress else {
            return
        }
        guard let settledAt = settings.scheduledSwitchesSettledAt else {
            settleScheduledProfileSwitches(at: now)
            await armScheduledProfileSwitchAlert(now: now)
            return
        }
        guard let due = ScheduledProfileSwitches.occurrences(of: settings.scheduledSwitches, after: settledAt, upTo: now, timeZone: scheduleTimeZone).first else {
            return
        }
        let name = due.entry.profileName

        guard now.timeIntervalSince(due.date) <= Self.scheduledProfileSwitchGrace else {
            log.error("Scheduled switch to %{public}@ at %{public}@ is too late to run", name, String(describing: due.date))
            settleScheduledProfileSwitches(at: now)
            await issueScheduledProfileSwitchFailedAlert(due, reason: String(format: NSLocalizedString("It is more than %1$d hours late.", comment: "Reason a scheduled profile switch did not run: too late (1: hours)"), Int(Self.scheduledProfileSwitchGrace.hours)))
            await armScheduledProfileSwitchAlert(now: now)
            return
        }
        guard therapyProfile(named: name) != nil else {
            settleScheduledProfileSwitches(at: now)
            await issueScheduledProfileSwitchFailedAlert(due, reason: TherapyProfileError.notFound(name).localizedDescription)
            await armScheduledProfileSwitchAlert(now: now)
            return
        }
        guard name != activeTherapyProfileName else {
            settleScheduledProfileSwitches(at: now)
            await armScheduledProfileSwitchAlert(now: now)
            return
        }
        if case .inProgress = pumpManager?.status.bolusState {
            log.default("Scheduled switch to %{public}@ waits for the bolus to finish", name)
            return
        }

        do {
            try await activateTherapyProfile(named: name, expectedFingerprint: nil, trigger: .scheduled, at: due.date)
            NotificationManager.sendScheduledProfileSwitchNotification(profileName: name, scheduledAt: due.date, switchedAt: now, timeZone: scheduleTimeZone)
            await armScheduledProfileSwitchAlert(now: now)
        } catch let error as TherapyProfileError where error.isTransientForScheduledSwitch {
            log.default("Scheduled switch to %{public}@ not run yet: %{public}@", name, error.localizedDescription)
            await armScheduledProfileSwitchAlert(now: now, reason: error.localizedDescription)
        } catch {
            log.error("Scheduled switch to %{public}@ failed: %{public}@", name, error.localizedDescription)
            settleScheduledProfileSwitches(at: now)
            await issueScheduledProfileSwitchFailedAlert(due, reason: error.localizedDescription)
            await armScheduledProfileSwitchAlert(now: now)
        }
    }

    private func settleScheduledProfileSwitches(at date: Date) {
        settingsManager.mutateLoopSettings { settings in
            settings.scheduledSwitchesSettledAt = date
        }
    }

    /// Arms one alert for 30 minutes after the next start that is not settled, which iOS delivers also when Loop is
    /// not running. A successful switch or a settle arms it for the following start instead; a retry of a start whose
    /// alert was delivered leaves it.
    func armScheduledProfileSwitchAlert(now: Date = Date(), reason: String? = nil) async {
        let identifier = pendingScheduledProfileSwitchAlertIdentifier
        let settledAt = settingsManager.loopSettings.scheduledSwitchesSettledAt ?? now
        let next = nextScheduledProfileSwitch(after: settledAt)
        let alertDate = next?.date.addingTimeInterval(Self.scheduledProfileSwitchLateAlertDelay)
        if let alertDate, alertDate <= now {
            // Delivered already; it stays until the start is settled.
            return
        }
        await scheduledProfileSwitchAlertIssuer?.retractAlert(identifier: identifier)
        guard let next, let alertDate else {
            return
        }
        let time = ScheduledProfileSwitches.localizedTime(next.entry.time)
        var body = String(format: NSLocalizedString("Loop has not been able to switch to %1$@ as scheduled at %2$@. Open Loop.", comment: "Alert body when a scheduled profile switch has not run (1: profile name, 2: time)"), next.entry.profileName, time)
        if let reason {
            body += "\n\n" + reason
        }
        let content = Alert.Content(title: NSLocalizedString("Profile Not Switched", comment: "Title of the alerts about a scheduled profile switch that did not run"),
                                    body: body,
                                    acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Acknowledge button of a scheduled profile switch alert"))
        await scheduledProfileSwitchAlertIssuer?.issueAlert(Alert(identifier: identifier,
                                                                  foregroundContent: content,
                                                                  backgroundContent: content,
                                                                  trigger: .delayed(interval: alertDate.timeIntervalSince(now)),
                                                                  interruptionLevel: .timeSensitive,
                                                                  categoryIdentifier: LoopNotificationCategory.scheduledProfileSwitch.rawValue))
    }

    private func issueScheduledProfileSwitchFailedAlert(_ occurrence: ScheduledProfileSwitchOccurrence, reason: String) async {
        let body = String(format: NSLocalizedString("The scheduled switch to %1$@ (%2$@) did not happen: %3$@", comment: "Alert body when a scheduled profile switch did not run (1: profile name, 2: weekday and time, 3: reason)"),
                          occurrence.entry.profileName, occurrence.entry.localizedWeekdayAndTime, reason)
        let content = Alert.Content(title: NSLocalizedString("Profile Not Switched", comment: "Title of the alerts about a scheduled profile switch that did not run"),
                                    body: body,
                                    acknowledgeActionButtonLabel: NSLocalizedString("OK", comment: "Acknowledge button of a scheduled profile switch alert"))
        let identifier = Alert.Identifier(managerIdentifier: Self.scheduledProfileSwitchManagerIdentifier,
                                          alertIdentifier: "\(occurrence.entry.id).\(Int(occurrence.date.timeIntervalSince1970))")
        await scheduledProfileSwitchAlertIssuer?.issueAlert(Alert(identifier: identifier,
                                                                  foregroundContent: content,
                                                                  backgroundContent: content,
                                                                  trigger: .immediate,
                                                                  interruptionLevel: .timeSensitive,
                                                                  categoryIdentifier: LoopNotificationCategory.scheduledProfileSwitch.rawValue))
    }
}

private extension PumpManagerStatus {
    /// A bolus is running or delivery is suspended, so a scheduled switch can not write the basal schedule now.
    var holdsScheduledProfileSwitch: Bool {
        if case .inProgress = bolusState {
            return true
        }
        switch basalDeliveryState {
        case .suspended, .suspending:
            return true
        default:
            return false
        }
    }
}

private extension TherapyProfileError {
    /// The pump can take the basal schedule later, so a scheduled switch tries again on the next run.
    var isTransientForScheduledSwitch: Bool {
        switch self {
        case .pumpSuspended, .pumpSyncFailed, .operationInProgress, .noPump:
            return true
        default:
            return false
        }
    }
}

extension DeviceDataManager: DeviceSupportDelegate {
    var availableSupports: [SupportUI] { [cgmManager, pumpManager].compactMap { $0 as? SupportUI } }

    func generateDiagnosticReport() async -> String {
        let report = [
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
            await deviceLog.generateDiagnosticReport()
            ]
        return report.joined(separator: "\n")
    }
}

extension DeviceDataManager: PumpManagerDeliveryDelegate {
    func send(bolus: Double?, tempBasal: TempBasalRecommendation?, decisionId: UUID?, to pumpManager: PumpManager) async throws {
        log.default("Enacting dose: %{public}@", String(describing: (bolus, tempBasal)))
        
        try await doseEnactor.enact(decisionId: decisionId, bolus: bolus, tempBasal: tempBasal, with: pumpManager)
    }

    var isAutomaticDosingActive: Bool {
        settingsManager.dosingEnabled && !isManualTempBasalRunning
    }

    var isPumpInoperable: Bool {
        guard let basalDeliveryState else {
            return true
        }
        return basalDeliveryState == .pumpInoperable 
    }
}

extension DeviceDataManager: DeviceStatusProvider {
    var pumpSupportedBasalRates: [Double]? {
        pumpManager?.supportedBasalRates
    }

    var pumpMaximumBasalScheduleEntryCount: Int? {
        pumpManager?.maximumBasalScheduleEntryCount
    }
}

extension DeviceDataManager: BolusStateProvider {
    var bolusState: LoopKit.PumpManagerStatus.BolusState? {
        return pumpManager?.status.bolusState
    }
}
