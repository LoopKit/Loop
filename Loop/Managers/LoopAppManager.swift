//
//  LoopAppManager.swift
//  Loop
//
//  Created by Darin Krauss on 2/16/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import UIKit
import Intents
import Combine
import LoopKit
import LoopKitUI
import MockKit
import HealthKit
import WidgetKit
import LoopCore
import LoopAlgorithm

#if targetEnvironment(simulator)
enum SimulatorError: Error {
    case remoteNotificationsNotAvailable
}
#endif

public protocol AlertPresenter: AnyObject {
    /// Present the alert view controller, with or without animation.
    /// - Parameters:
    ///   - viewControllerToPresent: The alert view controller to present.
    ///   - animated: Animate the alert view controller presentation or not.
    ///   - completion: Completion to call once view controller is presented.
    func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)?)

    /// Retract any alerts with the given identifier.  This includes both pending and delivered alerts.

    /// Dismiss the topmost view controller, presumably the alert view controller.
    /// - Parameters:
    ///   - animated: Animate the alert view controller dismissal or not.
    ///   - completion: Completion to call once view controller is dismissed.
    func dismissTopMost(animated: Bool, completion: (() -> Void)?)

    /// Dismiss an alert, even if it is not the top most alert.
    /// - Parameters:
    ///   - alertToDismiss: The alert to dismiss
    ///   - animated: Animate the alert view controller dismissal or not.
    ///   - completion: Completion to call once view controller is dismissed.
    func dismissAlert(_ alertToDismiss: UIAlertController, animated: Bool, completion: (() -> Void)?)
}

public extension AlertPresenter {
    func present(_ viewController: UIViewController, animated: Bool) { present(viewController, animated: animated, completion: nil) }
    func dismissTopMost(animated: Bool) { dismissTopMost(animated: animated, completion: nil) }
    func dismissAlert(_ alertToDismiss: UIAlertController, animated: Bool) { dismissAlert(alertToDismiss, animated: animated, completion: nil) }
}

protocol WindowProvider: AnyObject {
    var window: UIWindow? { get }
}

@MainActor
class LoopAppManager: NSObject {
    private enum State: Int {
        case initialize
        case checkProtectedDataAvailable
        case launchManagers
        case launchOnboarding
        case launchHomeScreen
        case launchComplete

        var next: State { State(rawValue: rawValue + 1) ?? .launchComplete }
    }

    private weak var windowProvider: WindowProvider?
    private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

    private var pluginManager: PluginManager!
    private var bluetoothStateManager: BluetoothStateManager!
    private var alertManager: AlertManager!
    private var trustedTimeChecker: TrustedTimeChecker!
    private var healthStore: HKHealthStore!
    private var carbStore: CarbStore!
    private var doseStore: DoseStore!
    private var glucoseStore: GlucoseStore!
    private var dosingDecisionStore: DosingDecisionStore!
    private var deviceDataManager: DeviceDataManager!
    private var onboardingManager: OnboardingManager!
    private var alertPermissionsChecker: AlertPermissionsChecker!
    private var supportManager: SupportManager!
    private var settingsManager: SettingsManager!
    private var loggingServicesManager = LoggingServicesManager()
    private var analyticsServicesManager = AnalyticsServicesManager()
    private(set) var testingScenariosManager: TestingScenariosManager?
    private var resetLoopManager: ResetLoopManager!
    private var deeplinkManager: DeeplinkManager!
    private var temporaryPresetsManager: TemporaryPresetsManager!
    private var loopDataManager: LoopDataManager!
    private var mealDetectionManager: MealDetectionManager!
    private var statusExtensionManager: ExtensionDataManager!
    private var watchManager: WatchDataManager!
    private var crashRecoveryManager: CrashRecoveryManager!
    private var cgmEventStore: CgmEventStore!
    private var servicesManager: ServicesManager!
    private var remoteDataServicesManager: RemoteDataServicesManager!
    private var statefulPluginManager: StatefulPluginManager!
    private var criticalEventLogExportManager: CriticalEventLogExportManager!
    private var deviceLog: PersistentDeviceLog!

    // HealthStorePreferredGlucoseUnitDidChange will be notified once the user completes the health access form. Set to .milligramsPerDeciliter until then
    public private(set) var displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)

    private var displayGlucoseUnitObservers = WeakSynchronizedSet<DisplayGlucoseUnitObserver>()

    private var state: State = .initialize

    private let log = DiagnosticLog(category: "LoopAppManager")
    private let widgetLog = DiagnosticLog(category: "LoopWidgets")

    private let automaticDosingStatus = AutomaticDosingStatus(automaticDosingEnabled: false, isAutomaticDosingAllowed: false)

    lazy private var cancellables = Set<AnyCancellable>()

    func initialize(windowProvider: WindowProvider, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(state == .initialize)

        self.windowProvider = windowProvider
        self.launchOptions = launchOptions
        
        if FeatureFlags.siriEnabled && INPreferences.siriAuthorizationStatus() == .notDetermined {
            INPreferences.requestSiriAuthorization { _ in }
        }

        self.state = state.next
    }

    func launch() {
        precondition(isLaunchPending)

        Task {
            await resumeLaunch()
        }
    }

    var isLaunchPending: Bool { state == .checkProtectedDataAvailable }

    var isLaunchComplete: Bool { state == .launchComplete }

    private func resumeLaunch() async {
        if state == .checkProtectedDataAvailable {
            checkProtectedDataAvailable()
        }
        if state == .launchManagers {
            await launchManagers()
        }
        if state == .launchOnboarding {
            launchOnboarding()
        }
        if state == .launchHomeScreen {
            await launchHomeScreen()
        }
        
        askUserToConfirmLoopReset()
    }

    private func checkProtectedDataAvailable() {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(state == .checkProtectedDataAvailable)

        guard isProtectedDataAvailable() else {
            log.default("Protected data not available; deferring launch...")
            return
        }

        self.state = state.next
    }

    private func launchManagers() async {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(state == .launchManagers)

        windowProvider?.window?.tintColor = .loopAccent
        OrientationLock.deviceOrientationController = self
        UNUserNotificationCenter.current().delegate = self

        resetLoopManager = ResetLoopManager(delegate: self)

        let localCacheDuration = Bundle.main.localCacheDuration
        let cacheStore = PersistenceController.controllerInAppGroupDirectory()

        pluginManager = PluginManager()


        bluetoothStateManager = BluetoothStateManager()
        alertManager = AlertManager(alertPresenter: self,
                                    userNotificationAlertScheduler: UserNotificationAlertScheduler(userNotificationCenter: UNUserNotificationCenter.current()),
                                    expireAfter: Bundle.main.localCacheDuration,
                                    bluetoothProvider: bluetoothStateManager,
                                    analyticsServicesManager: analyticsServicesManager)

        alertPermissionsChecker = AlertPermissionsChecker()
        alertPermissionsChecker.delegate = alertManager
        
        trustedTimeChecker = LoopTrustedTimeChecker(alertManager: alertManager)

        settingsManager = SettingsManager(
            cacheStore: cacheStore,
            expireAfter: localCacheDuration,
            alertMuter: alertManager.alertMuter,
            analyticsServicesManager: analyticsServicesManager
        )

        // Once settings manager is initialized, we can register for remote notifications
        if FeatureFlags.remoteCommandsEnabled {
            DispatchQueue.main.async {
#if targetEnvironment(simulator)
                self.remoteNotificationRegistrationDidFinish(.failure(SimulatorError.remoteNotificationsNotAvailable))
#else
                UIApplication.shared.registerForRemoteNotifications()
#endif
            }
        }

        healthStore = HKHealthStore()

        let carbHealthStore = HealthKitSampleStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitCarbSamplesFromOtherApps, // At some point we should let the user decide which apps they would like to import from.
            type: HealthKitSampleStore.carbType,
            observationStart: Date().addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval)
        )

        temporaryPresetsManager = TemporaryPresetsManager(settingsProvider: settingsManager)
        temporaryPresetsManager.overrideHistory.delegate = self

        temporaryPresetsManager.addTemporaryPresetObserver(alertManager)
        temporaryPresetsManager.addTemporaryPresetObserver(analyticsServicesManager)

        self.carbStore = CarbStore(
            healthKitSampleStore: carbHealthStore,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration
        )

        let insulinHealthStore = HealthKitSampleStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps: FeatureFlags.observeHealthKitDoseSamplesFromOtherApps,
            type: HealthKitSampleStore.insulinQuantityType,
            observationStart: Date().addingTimeInterval(-CarbMath.maximumAbsorptionTimeInterval)
        )

        self.doseStore = DoseStore(
            healthKitSampleStore: insulinHealthStore,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
            lastPumpEventsReconciliation: nil // PumpManager is nil at this point. Will update this via addPumpEvents below
        )

        let glucoseHealthStore = HealthKitSampleStore(
            healthStore: healthStore,
            observeHealthKitSamplesFromOtherApps:  FeatureFlags.observeHealthKitGlucoseSamplesFromOtherApps,
            type: HealthKitSampleStore.glucoseType,
            observationStart: Date().addingTimeInterval(-.hours(24))
        )

        self.glucoseStore = GlucoseStore(
            healthKitSampleStore: glucoseHealthStore,
            cacheStore: cacheStore,
            cacheLength: localCacheDuration,
            provenanceIdentifier: HKSource.default().bundleIdentifier
        )

        dosingDecisionStore = DosingDecisionStore(store: cacheStore, expireAfter: localCacheDuration)


        NotificationCenter.default.addObserver(forName: .HealthStorePreferredGlucoseUnitDidChange, object: healthStore, queue: nil) { [weak self] _ in
            guard let self else {
                return
            }

            Task { @MainActor in
                if let unit = await self.healthStore.cachedPreferredUnits(for: .bloodGlucose) {
                    self.displayGlucosePreference.unitDidChange(to: unit)
                    self.notifyObserversOfDisplayGlucoseUnitChange(to: unit)
                }
            }
        }

        let carbModel: CarbAbsorptionModel = FeatureFlags.nonlinearCarbModelEnabled ? .piecewiseLinear : .linear

        loopDataManager = LoopDataManager(
            lastLoopCompleted: ExtensionDataManager.context?.lastLoopCompleted,
            temporaryPresetsManager: temporaryPresetsManager,
            settingsProvider: settingsManager,
            doseStore: doseStore,
            glucoseStore: glucoseStore,
            carbStore: carbStore,
            dosingDecisionStore: dosingDecisionStore,
            automaticDosingStatus: automaticDosingStatus,
            trustedTimeOffset: { self.trustedTimeChecker.detectedSystemTimeOffset },
            analyticsServicesManager: analyticsServicesManager,
            carbAbsorptionModel: carbModel
        )

        cacheStore.delegate = loopDataManager

        crashRecoveryManager = CrashRecoveryManager(alertIssuer: alertManager)

        Task { @MainActor in
            alertManager.addAlertResponder(managerIdentifier: crashRecoveryManager.managerIdentifier, alertResponder: crashRecoveryManager)
        }

        cgmEventStore = CgmEventStore(cacheStore: cacheStore, cacheLength: localCacheDuration)

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


        remoteDataServicesManager = RemoteDataServicesManager(
            alertStore: alertManager.alertStore,
            carbStore: carbStore,
            doseStore: doseStore,
            dosingDecisionStore: dosingDecisionStore,
            glucoseStore: glucoseStore,
            cgmEventStore: cgmEventStore,
            settingsProvider: settingsManager,
            overrideHistory: temporaryPresetsManager.overrideHistory,
            insulinDeliveryStore: doseStore.insulinDeliveryStore,
            deviceLog: deviceLog,
            automationHistoryProvider: loopDataManager
        )

        settingsManager.remoteDataServicesManager = remoteDataServicesManager

        remoteDataServicesManager.triggerAllUploads()

        servicesManager = ServicesManager(
            pluginManager: pluginManager,
            alertManager: alertManager,
            analyticsServicesManager: analyticsServicesManager,
            loggingServicesManager: loggingServicesManager,
            remoteDataServicesManager: remoteDataServicesManager,
            settingsManager: settingsManager,
            servicesManagerDelegate: loopDataManager,
            servicesManagerDosingDelegate: self
        )

        statefulPluginManager = StatefulPluginManager(pluginManager: pluginManager, servicesManager: servicesManager)

        deviceDataManager = DeviceDataManager(pluginManager: pluginManager,
                                              deviceLog: deviceLog,
                                              alertManager: alertManager,
                                              settingsManager: settingsManager,
                                              healthStore: healthStore,
                                              carbStore: carbStore,
                                              doseStore: doseStore,
                                              glucoseStore: glucoseStore,
                                              cgmEventStore: cgmEventStore,
                                              uploadEventListener: remoteDataServicesManager,
                                              crashRecoveryManager: crashRecoveryManager,
                                              loopControl: loopDataManager,
                                              analyticsServicesManager: analyticsServicesManager,
                                              activeServicesProvider: servicesManager,
                                              activeStatefulPluginsProvider: statefulPluginManager,
                                              bluetoothProvider: bluetoothStateManager,
                                              alertPresenter: self,
                                              automaticDosingStatus: automaticDosingStatus,
                                              cacheStore: cacheStore,
                                              localCacheDuration: localCacheDuration,
                                              displayGlucosePreference: displayGlucosePreference,
                                              displayGlucoseUnitBroadcaster: self
        )

        dosingDecisionStore.delegate = deviceDataManager
        remoteDataServicesManager.delegate = deviceDataManager



        let criticalEventLogs: [CriticalEventLog] = [settingsManager.settingsStore, glucoseStore, carbStore, dosingDecisionStore, doseStore, deviceDataManager.deviceLog, alertManager.alertStore]
        criticalEventLogExportManager = CriticalEventLogExportManager(logs: criticalEventLogs,
                                                                      directory: FileManager.default.exportsDirectoryURL,
                                                                      historicalDuration: localCacheDuration)

        criticalEventLogExportManager.registerBackgroundTasks()


        statusExtensionManager = ExtensionDataManager(
            deviceDataManager: deviceDataManager,
            loopDataManager: loopDataManager,
            automaticDosingStatus: automaticDosingStatus,
            settingsManager: settingsManager,
            temporaryPresetsManager: temporaryPresetsManager
        )

        watchManager = WatchDataManager(
            deviceManager: deviceDataManager,
            settingsManager: settingsManager,
            loopDataManager: loopDataManager,
            carbStore: carbStore,
            glucoseStore: glucoseStore,
            analyticsServicesManager: analyticsServicesManager,
            temporaryPresetsManager: temporaryPresetsManager,
            healthStore: healthStore
        )

        self.mealDetectionManager = MealDetectionManager(
            algorithmStateProvider: loopDataManager,
            settingsProvider: temporaryPresetsManager,
            bolusStateProvider: deviceDataManager
        )

        loopDataManager.deliveryDelegate = deviceDataManager

        deviceDataManager.instantiateDeviceManagers()

        settingsManager.deviceStatusProvider = deviceDataManager
        settingsManager.displayGlucosePreference = displayGlucosePreference

        SharedLogging.instance = loggingServicesManager

        criticalEventLogExportManager.scheduleCriticalEventLogHistoricalExportBackgroundTask()


        supportManager = SupportManager(pluginManager: pluginManager,
                                        deviceSupportDelegate: deviceDataManager,
                                        servicesManager: servicesManager,
                                        alertIssuer: alertManager)
        
        setWhitelistedDevices()

        onboardingManager = OnboardingManager(pluginManager: pluginManager,
                                              bluetoothProvider: bluetoothStateManager,
                                              deviceDataManager: deviceDataManager, 
                                              settingsManager: settingsManager,
                                              statefulPluginManager: statefulPluginManager,
                                              servicesManager: servicesManager,
                                              loopDataManager: loopDataManager,
                                              supportManager: supportManager,
                                              windowProvider: windowProvider,
                                              userDefaults: UserDefaults.appGroup!)

        deeplinkManager = DeeplinkManager(rootViewController: rootViewController)

        for support in supportManager.availableSupports {
            if let analyticsService = support as? AnalyticsService {
                analyticsServicesManager.addService(analyticsService)
            }
            support.initializationComplete(for: deviceDataManager.allActivePlugins)
        }

        deviceDataManager.onboardingManager = onboardingManager

        // Analytics: user properties
        analyticsServicesManager.identifyAppName(Bundle.main.bundleDisplayName)

        if let workspaceGitRevision = BuildDetails.default.workspaceGitRevision {
            analyticsServicesManager.identifyWorkspaceGitRevision(workspaceGitRevision)
        }

        analyticsServicesManager.identify("Dosing Strategy", value: settingsManager.loopSettings.automaticDosingStrategy.analyticsValue)
        let serviceNames = servicesManager.activeServices.map { $0.pluginIdentifier }
        analyticsServicesManager.identify("Services", array: serviceNames)

        if FeatureFlags.scenariosEnabled {
            testingScenariosManager = TestingScenariosManager(
                deviceManager: deviceDataManager,
                supportManager: supportManager,
                pluginManager: pluginManager,
                carbStore: carbStore,
                settingsManager: settingsManager
            )
        }

        analyticsServicesManager.application(didFinishLaunchingWithOptions: launchOptions)

        automaticDosingStatus.$isAutomaticDosingAllowed
            .combineLatest(settingsManager.$dosingEnabled)
            .map { $0 && $1 }
            .assign(to: \.automaticDosingStatus.automaticDosingEnabled, on: self)
            .store(in: &cancellables)

        state = state.next

        await loopDataManager.updateDisplayState()

        NotificationCenter.default.publisher(for: .LoopCycleCompleted)
            .sink { [weak self] _ in
                Task {
                    await self?.loopCycleDidComplete()
                }
            }
            .store(in: &cancellables)
    }

    private func loopCycleDidComplete() async {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.widgetLog.default("Refreshing widget. Reason: Loop completed")
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func launchOnboarding() {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(state == .launchOnboarding)

        onboardingManager.launch {
            DispatchQueue.main.async {
                self.state = self.state.next
                self.alertManager.playbackAlertsFromPersistence()
                Task {
                    await self.resumeLaunch()
                }
            }
        }
    }

    private func launchHomeScreen() async {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(state == .launchHomeScreen)

        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: Self.self))
        let statusTableViewController = storyboard.instantiateViewController(withIdentifier: "MainStatusViewController") as! StatusTableViewController
        statusTableViewController.alertPermissionsChecker = alertPermissionsChecker
        statusTableViewController.alertMuter = alertManager.alertMuter
        statusTableViewController.automaticDosingStatus = automaticDosingStatus
        statusTableViewController.deviceManager = deviceDataManager
        statusTableViewController.onboardingManager = onboardingManager
        statusTableViewController.supportManager = supportManager
        statusTableViewController.testingScenariosManager = testingScenariosManager
        statusTableViewController.settingsManager = settingsManager
        statusTableViewController.temporaryPresetsManager = temporaryPresetsManager
        statusTableViewController.loopManager = loopDataManager
        statusTableViewController.diagnosticReportGenerator = self
        statusTableViewController.simulatedData = self
        statusTableViewController.analyticsServicesManager = analyticsServicesManager
        statusTableViewController.servicesManager = servicesManager
        statusTableViewController.carbStore = carbStore
        statusTableViewController.doseStore = doseStore
        statusTableViewController.criticalEventLogExportManager = criticalEventLogExportManager
        bluetoothStateManager.addBluetoothObserver(statusTableViewController)

        var rootNavigationController = rootViewController as? RootNavigationController
        if rootNavigationController == nil {
            rootNavigationController = RootNavigationController()
            rootViewController = rootNavigationController
        }

        rootNavigationController?.setViewControllers([statusTableViewController], animated: true)

        await deviceDataManager.refreshDeviceData()

        handleRemoteNotificationFromLaunchOptions()

        self.launchOptions = nil

        self.state = state.next

        alertManager.playbackAlertsFromPersistence()
    }

    // MARK: - Life Cycle

    func didBecomeActive() {
        if let rootViewController = rootViewController {
            AppExpirationAlerter.alertIfNeeded(viewControllerToPresentFrom: rootViewController)
        }
        settingsManager?.didBecomeActive()
        deviceDataManager?.didBecomeActive()
        alertManager?.inferDeliveredLoopNotRunningNotifications()
        
        widgetLog.default("Refreshing widget. Reason: App didBecomeActive")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Remote Notification
    
    func remoteNotificationRegistrationDidFinish(_ result: Swift.Result<Data,Error>) {
        if case .success(let token) = result {
            log.default("DeviceToken: %{public}@", token.hexadecimalString)
        }
        settingsManager.remoteNotificationRegistrationDidFinish(result)
    }

    private func handleRemoteNotificationFromLaunchOptions() {
        handleRemoteNotification(launchOptions?[.remoteNotification] as? [String: AnyObject])
    }

    @discardableResult
    func handleRemoteNotification(_ notification: [String: AnyObject]?) -> Bool {
        guard let notification = notification else {
            return false
        }
        servicesManager.handleRemoteNotification(notification)
        return true
    }
    
    // MARK: - Deeplinking
    
    func handle(_ url: URL) -> Bool {
        deeplinkManager.handle(url)
    }

    // MARK: - Continuity

    func userActivity(_ userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        if userActivity.activityType == NewCarbEntryIntent.className {
            log.default("Restoring %{public}@ intent", userActivity.activityType)
            rootViewController?.restoreUserActivityState(.forNewCarbEntry())
            return true
        }

        switch userActivity.activityType {
        case NSUserActivity.newCarbEntryActivityType,
             NSUserActivity.viewLoopStatusActivityType:
            log.default("Restoring %{public}@ activity", userActivity.activityType)
            if let rootViewController = rootViewController {
                restorationHandler([rootViewController])
            }
            return true
        default:
            return false
        }
    }

    // MARK: - Interface

    private static let defaultSupportedInterfaceOrientations = UIInterfaceOrientationMask.allButUpsideDown

    var supportedInterfaceOrientations = defaultSupportedInterfaceOrientations {
        didSet {
            if #available(iOS 16.0, *) {
                rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            } else {
                // Fallback on earlier versions
            }
        }
    }

    // MARK: - Private
    
    private func setWhitelistedDevices() {
        var whitelistedCGMs: Set<String> = []
        var whitelistedPumps: Set<String> = []
        
        supportManager.availableSupports.forEach {
            $0.deviceIdentifierWhitelist.cgmDevices.forEach({ whitelistedCGMs.insert($0) })
            $0.deviceIdentifierWhitelist.pumpDevices.forEach({ whitelistedPumps.insert($0) })
        }
        
        deviceDataManager.deviceWhitelist = DeviceWhitelist(cgmDevices: Array(whitelistedCGMs), pumpDevices: Array(whitelistedPumps))
    }

    private func isProtectedDataAvailable() -> Bool {
        let fileManager = FileManager.default
        do {
            let documentDirectory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fileURL = documentDirectory.appendingPathComponent("protection.test")
            guard fileManager.fileExists(atPath: fileURL.path) else {
                let contents = Data("unimportant".utf8)
                try? contents.write(to: fileURL, options: .completeFileProtectionUntilFirstUserAuthentication)
                // If file doesn't exist, we're at first start, which will be user directed.
                return true
            }
            let contents = try? Data(contentsOf: fileURL)
            return contents != nil
        } catch {
            log.error("Could not create after first unlock test file: %@", String(describing: error))
        }
        return false
    }
    
    private var rootViewController: UIViewController? {
        get { windowProvider?.window?.rootViewController }
        set { windowProvider?.window?.rootViewController = newValue }
    }
}

// MARK: - AlertPresenter

extension LoopAppManager: AlertPresenter {
    func present(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?) {
        DispatchQueue.main.async {
            self.rootViewController?.topmostViewController.present(viewControllerToPresent, animated: animated, completion: completion)
        }
    }

    func dismissTopMost(animated: Bool, completion: (() -> Void)?) {
        rootViewController?.topmostViewController.dismiss(animated: animated, completion: completion)
    }

    func dismissAlert(_ alertToDismiss: UIAlertController, animated: Bool, completion: (() -> Void)?) {
        if rootViewController?.topmostViewController == alertToDismiss {
            dismissTopMost(animated: animated, completion: completion)
        } else {
            // check if the alert to dismiss is presenting another alert (and so on)
            // calling dismiss() on an alert presenting another alert will only dismiss the presented alert
            // (and any other alerts presented by the presented alert)

            // get the stack of presented alerts that would be undesirably dismissed
            var presentedAlerts: [UIAlertController] = []
            var currentAlert = alertToDismiss
            while let presentedAlert = currentAlert.presentedViewController as? UIAlertController {
                presentedAlerts.append(presentedAlert)
                currentAlert = presentedAlert
            }

            if presentedAlerts.isEmpty {
                alertToDismiss.dismiss(animated: animated, completion: completion)
            } else {
                // Do not animate any of these view transitions, since the alert to dismiss is not at the top of the stack

                // dismiss all the child presented alerts.
                // Calling dismiss() on a VC that is presenting an other VC will dismiss the presented VC and all of its child presented VCs
                alertToDismiss.dismiss(animated: false) {
                    // dismiss the desired alert
                    // Calling dismiss() on a VC that is NOT presenting any other VCs will dismiss said VC
                    alertToDismiss.dismiss(animated: false) {
                        // present the child alerts that were undesirably dismissed
                        var orderedPresentationBlock: (() -> Void)? = nil
                        for alert in presentedAlerts.reversed() {
                            if alert == presentedAlerts.last {
                                orderedPresentationBlock = {
                                    self.present(alert, animated: false, completion: completion)
                                }
                            } else {
                                orderedPresentationBlock = {
                                    self.present(alert, animated: false, completion: orderedPresentationBlock)
                                }
                            }
                        }
                        orderedPresentationBlock?()
                    }
                }
            }
        }
    }
}

protocol DisplayGlucoseUnitBroadcaster: AnyObject {
    func addDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver)
    func removeDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver)
    func notifyObserversOfDisplayGlucoseUnitChange(to displayGlucoseUnit: HKUnit)
}

extension LoopAppManager: DisplayGlucoseUnitBroadcaster {
    func addDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver) {
        let queue = DispatchQueue.main
        displayGlucoseUnitObservers.insert(observer, queue: queue)
        queue.async {
            observer.unitDidChange(to: self.displayGlucosePreference.unit)
        }
    }

    func removeDisplayGlucoseUnitObserver(_ observer: DisplayGlucoseUnitObserver) {
        displayGlucoseUnitObservers.removeElement(observer)
        displayGlucoseUnitObservers.cleanupDeallocatedElements()
    }

    func notifyObserversOfDisplayGlucoseUnitChange(to displayGlucoseUnit: HKUnit) {
        self.displayGlucoseUnitObservers.forEach {
            $0.unitDidChange(to: displayGlucoseUnit)
        }
    }
}

// MARK: - DeviceOrientationController

extension LoopAppManager: DeviceOrientationController {
    func setDefaultSupportedInferfaceOrientations() {
        supportedInterfaceOrientations = Self.defaultSupportedInterfaceOrientations
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension LoopAppManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        switch notification.request.identifier {
        // TODO: Until these notifications are converted to use the new alert system, they shall still show in the foreground
        case LoopNotificationCategory.bolusFailure.rawValue,
             LoopNotificationCategory.pumpBatteryLow.rawValue,
             LoopNotificationCategory.pumpExpired.rawValue,
             LoopNotificationCategory.pumpFault.rawValue,
             LoopNotificationCategory.remoteBolus.rawValue,
             LoopNotificationCategory.remoteBolusFailure.rawValue,
             LoopNotificationCategory.remoteCarbs.rawValue,
             LoopNotificationCategory.remoteCarbsFailure.rawValue,
             LoopNotificationCategory.missedMeal.rawValue:
            completionHandler([.badge, .sound, .list, .banner])
        default:
            // For all others, banners are not to be displayed while in the foreground
            completionHandler([.badge, .sound, .list])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case NotificationManager.Action.retryBolus.rawValue:
            if  let units = response.notification.request.content.userInfo[LoopNotificationUserInfoKey.bolusAmount.rawValue] as? Double,
                let startDate = response.notification.request.content.userInfo[LoopNotificationUserInfoKey.bolusStartDate.rawValue] as? Date,
                let activationTypeRawValue = response.notification.request.content.userInfo[LoopNotificationUserInfoKey.bolusActivationType.rawValue] as? BolusActivationType.RawValue,
                let activationType = BolusActivationType(rawValue: activationTypeRawValue),
                startDate.timeIntervalSinceNow >= TimeInterval(minutes: -5)
            {
                analyticsServicesManager.didRetryBolus()
                
                Task { @MainActor in
                    try? await deviceDataManager?.enactBolus(units: units, activationType: activationType)
                    completionHandler()
                }
            }
        case NotificationManager.Action.acknowledgeAlert.rawValue:
            let userInfo = response.notification.request.content.userInfo
            if let alertIdentifier = userInfo[LoopNotificationUserInfoKey.alertTypeID.rawValue] as? Alert.AlertIdentifier,
               let managerIdentifier = userInfo[LoopNotificationUserInfoKey.managerIDForAlert.rawValue] as? String {
                alertManager?.acknowledgeAlert(identifier: Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: alertIdentifier))
            }
        case UNNotificationDefaultActionIdentifier:
            guard response.notification.request.identifier == LoopNotificationCategory.missedMeal.rawValue else {
                break
            }

            let carbActivity = NSUserActivity.forNewCarbEntry()
            let userInfo = response.notification.request.content.userInfo
            
            if
                let mealTime = userInfo[LoopNotificationUserInfoKey.missedMealTime.rawValue] as? Date,
                let carbAmount = userInfo[LoopNotificationUserInfoKey.missedMealCarbAmount.rawValue] as? Double
            {
                let missedEntry = NewCarbEntry(quantity: HKQuantity(unit: .gram(),
                                                                         doubleValue: carbAmount),
                                                    startDate: mealTime,
                                                    foodType: nil,
                                                    absorptionTime: nil)
                carbActivity.update(from: missedEntry, isMissedMeal: true)
            }
            
            rootViewController?.restoreUserActivityState(carbActivity)
            
        default:
            break
        }

        completionHandler()
    }

}


// MARK: - UNUserNotificationCenterDelegate

extension LoopAppManager: TemporaryScheduleOverrideHistoryDelegate {
    func temporaryScheduleOverrideHistoryDidUpdate(_ history: TemporaryScheduleOverrideHistory) {
        UserDefaults.appGroup?.overrideHistory = history
        remoteDataServicesManager.triggerUpload(for: .overrides)
    }
}

extension LoopAppManager: ResetLoopManagerDelegate {
    func askUserToConfirmLoopReset() {
        resetLoopManager.askUserToConfirmLoopReset()
    }
    
    func presentConfirmationAlert(confirmAction: @escaping (PumpManager?, @escaping () -> Void) -> Void, cancelAction: @escaping () -> Void) {
        alertManager.presentLoopResetConfirmationAlert(
            confirmAction: { [weak self] completion in
                confirmAction(self?.deviceDataManager.pumpManager, completion)
            },
            cancelAction: cancelAction
        )
    }
    
    func loopWillReset() {
        supportManager.availableSupports.forEach { supportUI in
            supportUI.loopWillReset()
        }
    }
    
    func loopDidReset() {
        supportManager.availableSupports.forEach { supportUI in
            supportUI.loopDidReset()
        }
    }
    
    func resetTestingData(completion: @escaping () -> Void) {
        deviceDataManager.deleteTestingCGMData { [weak deviceDataManager] _ in
            deviceDataManager?.deleteTestingPumpData { _ in
                completion()
            }
        }
    }
    
    func presentCouldNotResetLoopAlert(error: Error) {
        alertManager.presentCouldNotResetLoopAlert(error: error)
    }
}

// MARK: - ServicesManagerDosingDelegate

extension LoopAppManager: ServicesManagerDosingDelegate {
    func deliverBolus(amountInUnits: Double) async throws {
        try await deviceDataManager.enactBolus(units: amountInUnits, activationType: .manualNoRecommendation)
    }
}

protocol DiagnosticReportGenerator: AnyObject {
    func generateDiagnosticReport() async -> String
}


extension LoopAppManager: DiagnosticReportGenerator {
    /// Generates a diagnostic report about the current state
    ///
    /// This operation is performed asynchronously and the completion will be executed on an arbitrary background queue.
    ///
    /// - parameter completion: A closure called once the report has been generated. The closure takes a single argument of the report string.
    func generateDiagnosticReport() async -> String {

        let entries: [String] = [
            "## Build Details",
            "* appNameAndVersion: \(Bundle.main.localizedNameAndVersion)",
            "* profileExpiration: \(BuildDetails.default.profileExpirationString)",
            "* gitRevision: \(BuildDetails.default.gitRevision ?? "N/A")",
            "* gitBranch: \(BuildDetails.default.gitBranch ?? "N/A")",
            "* workspaceGitRevision: \(BuildDetails.default.workspaceGitRevision ?? "N/A")",
            "* workspaceGitBranch: \(BuildDetails.default.workspaceGitBranch ?? "N/A")",
            "* sourceRoot: \(BuildDetails.default.sourceRoot ?? "N/A")",
            "* buildDateString: \(BuildDetails.default.buildDateString ?? "N/A")",
            "* xcodeVersion: \(BuildDetails.default.xcodeVersion ?? "N/A")",
            "",
            "## FeatureFlags",
            "\(FeatureFlags)",
            "",
            await alertManager.generateDiagnosticReport(),
            await deviceDataManager.generateDiagnosticReport(),
            "",
            String(reflecting: self.watchManager),
            "",
            String(reflecting: self.statusExtensionManager),
            "",
            await loopDataManager.generateDiagnosticReport(),
            "",
            await self.glucoseStore.generateDiagnosticReport(),
            "",
            await self.carbStore.generateDiagnosticReport(),
            "",
            await self.doseStore.generateDiagnosticReport(),
            "",
            await self.mealDetectionManager.generateDiagnosticReport(),
            "",
            await UNUserNotificationCenter.current().generateDiagnosticReport(),
            "",
            UIDevice.current.generateDiagnosticReport(),
            ""
        ]
        return entries.joined(separator: "\n")
    }
}


// MARK: SimulatedData

protocol SimulatedData {
    func generateSimulatedHistoricalCoreData(completion: @escaping (Error?) -> Void)
    func purgeHistoricalCoreData(completion: @escaping (Error?) -> Void)
}

extension LoopAppManager: SimulatedData {
    func generateSimulatedHistoricalCoreData(completion: @escaping (Error?) -> Void) {
        guard FeatureFlags.simulatedCoreDataEnabled else {
            fatalError("\(#function) should be invoked only when simulated core data is enabled")
        }

        settingsManager.settingsStore.generateSimulatedHistoricalSettingsObjects() { error in
            guard error == nil else {
                completion(error)
                return
            }
            Task { @MainActor in
                guard FeatureFlags.simulatedCoreDataEnabled else {
                    fatalError("\(#function) should be invoked only when simulated core data is enabled")
                }

                self.glucoseStore.generateSimulatedHistoricalGlucoseObjects() { error in
                    guard error == nil else {
                        completion(error)
                        return
                    }
                    self.carbStore.generateSimulatedHistoricalCarbObjects() { error in
                        guard error == nil else {
                            completion(error)
                            return
                        }
                        self.dosingDecisionStore.generateSimulatedHistoricalDosingDecisionObjects() { error in
                            Task {
                                guard error == nil else {
                                    completion(error)
                                    return
                                }
                                do {
                                    try await self.doseStore.generateSimulatedHistoricalPumpEvents()
                                } catch {
                                    completion(error)
                                    return
                                }
                                self.deviceDataManager.deviceLog.generateSimulatedHistoricalDeviceLogEntries() { error in
                                    guard error == nil else {
                                        completion(error)
                                        return
                                    }
                                    self.alertManager.alertStore.generateSimulatedHistoricalStoredAlerts(completion: completion)
                                }
                            }
                        }
                    }
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
            self.deviceDataManager.deviceLog.purgeHistoricalDeviceLogEntries() { error in
                guard error == nil else {
                    completion(error)
                    return
                }
                Task { @MainActor in
                    do {
                        try await self.doseStore.purgeHistoricalPumpEvents()
                    } catch {
                        completion(error)
                        return
                    }
                    self.dosingDecisionStore.purgeHistoricalDosingDecisionObjects() { error in
                        guard error == nil else {
                            completion(error)
                            return
                        }
                        self.carbStore.purgeHistoricalCarbObjects() { error in
                            guard error == nil else {
                                completion(error)
                                return
                            }
                            self.glucoseStore.purgeHistoricalGlucoseObjects() { error in
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
        }
    }
}

