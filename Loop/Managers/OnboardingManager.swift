//
//  OnboardingManager.swift
//  Loop
//
//  Created by Darin Krauss on 2/19/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import os.log
import HealthKit
import LoopKit
import LoopKitUI

class OnboardingManager {
    private let pluginManager: PluginManager
    private let bluetoothProvider: BluetoothProvider
    private let deviceDataManager: DeviceDataManager
    private let servicesManager: ServicesManager
    private let loopDataManager: LoopDataManager
    private let supportManager: SupportManager
    private weak var windowProvider: WindowProvider?
    private let userDefaults: UserDefaults

    private let log = OSLog(category: "OnboardingManager")

    @Published public private(set) var isSuspended: Bool {
        didSet { userDefaults.onboardingManagerIsSuspended = isSuspended }
    }

    @Published public private(set) var isComplete: Bool {
        didSet { userDefaults.onboardingManagerIsComplete = isComplete }
    }
    private var completedOnboardingIdentifiers: [String] = [] {
        didSet { userDefaults.onboardingManagerCompletedOnboardingIdentifiers = completedOnboardingIdentifiers }
    }
    private var activeOnboarding: OnboardingUI? = nil {
        didSet { userDefaults.onboardingManagerActiveOnboardingRawValue = activeOnboarding?.rawValue }
    }

    private var onboardingCompletion: (() -> Void)?

    init(pluginManager: PluginManager, bluetoothProvider: BluetoothProvider, deviceDataManager: DeviceDataManager, servicesManager: ServicesManager, loopDataManager: LoopDataManager, supportManager: SupportManager, windowProvider: WindowProvider?, userDefaults: UserDefaults = .standard) {
        self.pluginManager = pluginManager
        self.bluetoothProvider = bluetoothProvider
        self.deviceDataManager = deviceDataManager
        self.servicesManager = servicesManager
        self.loopDataManager = loopDataManager
        self.supportManager = supportManager
        self.windowProvider = windowProvider
        self.userDefaults = userDefaults

        self.isSuspended = userDefaults.onboardingManagerIsSuspended

        self.isComplete = userDefaults.onboardingManagerIsComplete && loopDataManager.therapySettings.isComplete
        if !isComplete {
            if loopDataManager.therapySettings.isComplete {
                self.completedOnboardingIdentifiers = userDefaults.onboardingManagerCompletedOnboardingIdentifiers
            }
            if let activeOnboardingRawValue = userDefaults.onboardingManagerActiveOnboardingRawValue {
                self.activeOnboarding = onboardingFromRawValue(activeOnboardingRawValue)
                self.activeOnboarding?.onboardingDelegate = self
            }
        }
    }

    func launch(_ completion: @escaping () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(self.onboardingCompletion == nil)

        self.onboardingCompletion = completion
        continueOnboarding()
    }

    func resume() {
        dispatchPrecondition(condition: .onQueue(.main))
        precondition(self.onboardingCompletion == nil)

        self.onboardingCompletion = {
            self.windowProvider?.window?.rootViewController?.dismiss(animated: true, completion: nil)
        }
        continueOnboarding(allowResume: true)
    }

    private func continueOnboarding(allowResume: Bool = false) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !isComplete else {
            authorizeAndComplete()
            return
        }
        guard let onboarding = nextActiveOnboarding else {
            authorizeAndComplete()
            return
        }
        guard !isSuspended || allowResume else {
            complete()
            return
        }

        let resuming = isSuspended
        self.isSuspended = false

        if !displayOnboarding(onboarding, resuming: resuming) {
            completeActiveOnboarding()
        }
    }

    private var nextActiveOnboarding: OnboardingUI? {
        if activeOnboarding == nil {
            self.activeOnboarding = nextOnboarding
            self.activeOnboarding?.onboardingDelegate = self
        }
        return activeOnboarding
    }

    private var nextOnboarding: OnboardingUI? {
        let onboardingIdentifiers = pluginManager.availableOnboardingIdentifiers.filter { !completedOnboardingIdentifiers.contains($0) }
        for onboardingIdentifier in onboardingIdentifiers {
            guard let onboardingType = onboardingTypeByIdentifier(onboardingIdentifier) else {
                continue
            }

            let onboarding = onboardingType.createOnboarding()
            guard !onboarding.isOnboarded else {
                completedOnboardingIdentifiers.append(onboarding.onboardingIdentifier)
                continue
            }

            return onboarding
        }
        return nil
    }

    private func displayOnboarding(_ onboarding: OnboardingUI, resuming: Bool) -> Bool {
        var onboardingViewController = onboarding.onboardingViewController(onboardingProvider: self, displayGlucoseUnitObservable: deviceDataManager.displayGlucoseUnitObservable, colorPalette: .default)
        onboardingViewController.cgmManagerOnboardingDelegate = deviceDataManager
        onboardingViewController.pumpManagerOnboardingDelegate = deviceDataManager
        onboardingViewController.serviceOnboardingDelegate = servicesManager
        onboardingViewController.completionDelegate = self

        guard !onboarding.isOnboarded else {
            return false
        }

        if resuming {
            onboardingViewController.isModalInPresentation = true
            windowProvider?.window?.rootViewController?.present(onboardingViewController, animated: true, completion: nil)
        } else {
            windowProvider?.window?.rootViewController = onboardingViewController
        }
        return true
    }

    private func completeActiveOnboarding() {
        dispatchPrecondition(condition: .onQueue(.main))

        if let activeOnboarding = self.activeOnboarding, !isSuspended {
            completedOnboardingIdentifiers.append(activeOnboarding.onboardingIdentifier)
            self.activeOnboarding = nil
        }
        continueOnboarding()
    }

    private func ensureAuthorization(_ completion: @escaping () -> Void) {
        ensureNotificationAuthorization {
            self.ensureHealthStoreAuthorization {
                self.ensureBluetoothAuthorization(completion)
            }
        }
    }

    private func ensureNotificationAuthorization(_ completion: @escaping () -> Void) {
        getNotificationAuthorization { authorization in
            guard authorization == .notDetermined else {
                completion()
                return
            }
            self.authorizeNotification { _ in completion() }
        }
    }

    private func ensureHealthStoreAuthorization(_ completion: @escaping () -> Void) {
        getHealthStoreAuthorization { authorization in
            guard authorization == .notDetermined else {
                completion()
                return
            }
            self.authorizeHealthStore { _ in completion() }
        }
    }

    private func ensureBluetoothAuthorization(_ completion: @escaping () -> Void) {
        guard bluetoothAuthorization == .notDetermined else {
            completion()
            return
        }
        authorizeBluetooth { _ in completion() }
    }

    private func authorizeAndComplete() {
        ensureAuthorization {
            DispatchQueue.main.async {
                self.isComplete = true
                self.complete()
            }
        }
    }

    private func complete() {
        dispatchPrecondition(condition: .onQueue(.main))

        if let completion = onboardingCompletion {
            self.onboardingCompletion = nil
            completion()
        }
    }

    // MARK: - State

    private func onboardingFromRawValue(_ rawValue: OnboardingUI.RawValue) -> OnboardingUI? {
        guard let onboardingType = onboardingTypeFromRawValue(rawValue),
              let rawState = rawValue["state"] as? OnboardingUI.RawState
        else {
            return nil
        }

        return onboardingType.init(rawState: rawState)
    }

    private func onboardingTypeFromRawValue(_ rawValue: OnboardingUI.RawValue) -> OnboardingUI.Type? {
        guard let identifier = rawValue["onboardingIdentifier"] as? String else {
            return nil
        }

        return onboardingTypeByIdentifier(identifier)
    }

    private func onboardingTypeByIdentifier(_ identifier: String) -> OnboardingUI.Type? {
        return pluginManager.getOnboardingTypeByIdentifier(identifier)
    }
}

// MARK: - OnboardingDelegate

extension OnboardingManager: OnboardingDelegate {
    func onboardingDidUpdateState(_ onboarding: OnboardingUI) {
        guard onboarding.onboardingIdentifier == activeOnboarding?.onboardingIdentifier else { return }
        userDefaults.onboardingManagerActiveOnboardingRawValue = onboarding.rawValue
    }

    func onboarding(_ onboarding: OnboardingUI, hasNewTherapySettings therapySettings: TherapySettings) {
        guard onboarding.onboardingIdentifier == activeOnboarding?.onboardingIdentifier else { return }
        loopDataManager.therapySettings = therapySettings
    }

    func onboarding(_ onboarding: OnboardingUI, hasNewDosingEnabled dosingEnabled: Bool) {
        guard onboarding.onboardingIdentifier == activeOnboarding?.onboardingIdentifier else { return }
        loopDataManager.mutateSettings { settings in
            settings.dosingEnabled = dosingEnabled
        }
    }

    func onboardingDidSuspend(_ onboarding: OnboardingUI) {
        log.debug("OnboardingUI %@ did suspend", onboarding.onboardingIdentifier)
        guard onboarding.onboardingIdentifier == activeOnboarding?.onboardingIdentifier else { return }
        self.isSuspended = true
    }
}

// MARK: - CompletionDelegate

extension OnboardingManager: CompletionDelegate {
    func completionNotifyingDidComplete(_ object: CompletionNotifying) {
        DispatchQueue.main.async {
            guard let activeOnboarding = self.activeOnboarding else {
                return
            }

            self.log.debug("completionNotifyingDidComplete during activeOnboarding", activeOnboarding.onboardingIdentifier)

            // The `completionNotifyingDidComplete` callback can be called by an onboarding plugin to signal that the user is done with
            // the onboarding UI, like when pausing, so the onboarding UI can be dismissed. This doesn't necessarily mean that the
            // onboarding is finished/complete. So we check to see if onboarding is finished here before calling `completeActiveOnboarding`
            if activeOnboarding.isOnboarded {
                self.completeActiveOnboarding()
            }

            self.complete()
        }
    }
}

// MARK: - NotificationAuthorizationProvider

extension OnboardingManager: NotificationAuthorizationProvider {
    func getNotificationAuthorization(_ completion: @escaping (NotificationAuthorization) -> Void) {
        NotificationManager.getAuthorization { completion(NotificationAuthorization($0)) }
    }

    func authorizeNotification(_ completion: @escaping (NotificationAuthorization) -> Void) {
        NotificationManager.authorize{ completion(NotificationAuthorization($0)) }
    }
}

// MARK: - HealthStoreAuthorizationProvider

extension OnboardingManager: HealthStoreAuthorizationProvider {
    func getHealthStoreAuthorization(_ completion: @escaping (HealthStoreAuthorization) -> Void) {
        deviceDataManager.getHealthStoreAuthorization { completion(HealthStoreAuthorization($0)) }
    }

    func authorizeHealthStore(_ completion: @escaping (HealthStoreAuthorization) -> Void) {
        deviceDataManager.authorizeHealthStore { completion(HealthStoreAuthorization($0)) }
    }
}

// MARK: - BluetoothProvider

extension OnboardingManager: BluetoothProvider {
    var bluetoothAuthorization: BluetoothAuthorization { bluetoothProvider.bluetoothAuthorization }

    var bluetoothState: BluetoothState { bluetoothProvider.bluetoothState }

    func authorizeBluetooth(_ completion: @escaping (BluetoothAuthorization) -> Void) { bluetoothProvider.authorizeBluetooth(completion) }

    func addBluetoothObserver(_ observer: BluetoothObserver, queue: DispatchQueue) { bluetoothProvider.addBluetoothObserver(observer, queue: queue) }

    func removeBluetoothObserver(_ observer: BluetoothObserver) { bluetoothProvider.removeBluetoothObserver(observer) }
}

// MARK: - CGMManagerProvider

extension OnboardingManager: CGMManagerProvider {
    var activeCGMManager: CGMManager? { deviceDataManager.cgmManager }

    var availableCGMManagers: [CGMManagerDescriptor] { deviceDataManager.availableCGMManagers }

    func imageForCGMManager(withIdentifier identifier: String) -> UIImage? {
        guard let cgmManagerType = deviceDataManager.cgmManagerTypeByIdentifier(identifier) else {
            return nil
        }
        return cgmManagerType.onboardingImage
    }

    func onboardCGMManager(withIdentifier identifier: String, prefersToSkipUserInteraction: Bool) -> Swift.Result<OnboardingResult<CGMManagerViewController, CGMManager>, Error> {
        guard let cgmManager = deviceDataManager.cgmManager else {
            return deviceDataManager.setupCGMManager(withIdentifier: identifier, prefersToSkipUserInteraction: prefersToSkipUserInteraction)
        }
        guard cgmManager.managerIdentifier == identifier else {
            return .failure(OnboardingError.invalidState)
        }

        if cgmManager.isOnboarded {
            return .success(.createdAndOnboarded(cgmManager))
        }

        guard let cgmManagerUI = cgmManager as? CGMManagerUI else {
            return .failure(OnboardingError.invalidState)
        }

        return .success(.userInteractionRequired(cgmManagerUI.settingsViewController(bluetoothProvider: self, displayGlucoseUnitObservable: deviceDataManager.displayGlucoseUnitObservable, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures)))
    }
}

// MARK: - PumpManagerProvider

extension OnboardingManager: PumpManagerProvider {
    var activePumpManager: PumpManager? { deviceDataManager.pumpManager }

    var availablePumpManagers: [PumpManagerDescriptor] { deviceDataManager.availablePumpManagers }

    func imageForPumpManager(withIdentifier identifier: String) -> UIImage? {
        guard let pumpManagerType = deviceDataManager.pumpManagerTypeByIdentifier(identifier) else {
            return nil
        }
        return pumpManagerType.onboardingImage
    }

    func supportedIncrementsForPumpManager(withIdentifier identifier: String) -> PumpSupportedIncrements? {
        guard let pumpManagerType = deviceDataManager.pumpManagerTypeByIdentifier(identifier) else {
            return nil
        }
        return PumpSupportedIncrements(basalRates: pumpManagerType.onboardingSupportedBasalRates,
                                       bolusVolumes: pumpManagerType.onboardingSupportedBolusVolumes,
                                       maximumBolusVolumes: pumpManagerType.onboardingSupportedMaximumBolusVolumes,
                                       maximumBasalScheduleEntryCount: pumpManagerType.onboardingMaximumBasalScheduleEntryCount)
    }

    func onboardPumpManager(withIdentifier identifier: String, initialSettings settings: PumpManagerSetupSettings, prefersToSkipUserInteraction: Bool) -> Swift.Result<OnboardingResult<PumpManagerViewController, PumpManager>, Error> {
        guard let pumpManager = deviceDataManager.pumpManager else {
            return deviceDataManager.setupPumpManager(withIdentifier: identifier, initialSettings: settings, prefersToSkipUserInteraction: prefersToSkipUserInteraction)
        }
        guard pumpManager.managerIdentifier == identifier else {
            return .failure(OnboardingError.invalidState)
        }

        if pumpManager.isOnboarded {
            return .success(.createdAndOnboarded(pumpManager))
        }

        return .success(.userInteractionRequired(pumpManager.settingsViewController(bluetoothProvider: self, colorPalette: .default, allowDebugFeatures: FeatureFlags.allowDebugFeatures, allowedInsulinTypes: deviceDataManager.allowedInsulinTypes)))
    }
}

// MARK: - ServiceProvider

extension OnboardingManager: ServiceProvider {
    var activeServices: [Service] { servicesManager.activeServices }

    var availableServices: [ServiceDescriptor] { servicesManager.availableServices }

    func onboardService(withIdentifier identifier: String) -> Swift.Result<OnboardingResult<ServiceViewController, Service>, Error> {
        guard let service = activeServices.first(where: { $0.serviceIdentifier == identifier }) else {
            return servicesManager.setupService(withIdentifier: identifier)
        }

        if service.isOnboarded {
            return .success(.createdAndOnboarded(service))
        }

        guard let serviceUI = service as? ServiceUI else {
            return .failure(OnboardingError.invalidState)
        }

        return .success(.userInteractionRequired(serviceUI.settingsViewController(colorPalette: .default)))
    }
}

// MARK: - TherapySettingsProvider
extension OnboardingManager: TherapySettingsProvider {
    var onboardingTherapySettings: TherapySettings {
        return loopDataManager.therapySettings
    }
}

// MARK: - OnboardingProvider

extension OnboardingManager: OnboardingProvider {
    var allowDebugFeatures: Bool { FeatureFlags.allowDebugFeatures }   // NOTE: DEBUG FEATURES - DEBUG AND TEST ONLY
}

// MARK: - SupportProvider

extension OnboardingManager: SupportProvider {
    var availableSupports: [SupportUI] { supportManager.availableSupports }
}

// MARK: - OnboardingUI

fileprivate extension OnboardingUI {
    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "onboardingIdentifier": onboardingIdentifier,
            "state": rawState
        ]
    }
}

// MARK: - OnboardingError

enum OnboardingError: LocalizedError {
    case invalidState

    var errorDescription: String? {
        switch self {
        case .invalidState:
            return NSLocalizedString("An unexpected onboarding error state occurred.", comment: "Invalid onboarding state")
        }
    }
}

// MARK: - UserDefaults

fileprivate extension UserDefaults {
    private enum Key: String {
        case onboardingManagerIsSuspended = "com.loopkit.Loop.OnboardingManager.IsSuspended"
        case onboardingManagerIsComplete = "com.loopkit.Loop.OnboardingManager.IsComplete"
        case onboardingManagerCompletedOnboardingIdentifiers = "com.loopkit.Loop.OnboardingManager.CompletedOnboardingIdentifiers"
        case onboardingManagerActiveOnboardingRawValue = "com.loopkit.Loop.OnboardingManager.ActiveOnboardingRawValue"
    }

    var onboardingManagerIsSuspended: Bool {
        get { bool(forKey: Key.onboardingManagerIsSuspended.rawValue) }
        set { set(newValue, forKey: Key.onboardingManagerIsSuspended.rawValue) }
    }

    var onboardingManagerIsComplete: Bool {
        get { bool(forKey: Key.onboardingManagerIsComplete.rawValue) }
        set { set(newValue, forKey: Key.onboardingManagerIsComplete.rawValue) }
    }

    var onboardingManagerCompletedOnboardingIdentifiers: [String] {
        get { array(forKey: Key.onboardingManagerCompletedOnboardingIdentifiers.rawValue) as? [String] ?? [] }
        set { set(newValue, forKey: Key.onboardingManagerCompletedOnboardingIdentifiers.rawValue) }
    }

    var onboardingManagerActiveOnboardingRawValue: OnboardingUI.RawValue? {
        get { object(forKey: Key.onboardingManagerActiveOnboardingRawValue.rawValue) as? OnboardingUI.RawValue }
        set { set(newValue, forKey: Key.onboardingManagerActiveOnboardingRawValue.rawValue) }
    }
}

// MARK: - NotificationAuthorization

extension NotificationAuthorization {
    init(_ authorization: UNAuthorizationStatus) {
        switch authorization {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .denied
        @unknown default:
            self = .notDetermined
        }
    }
}

// MARK: - HealthStoreAuthorization

extension HealthStoreAuthorization {
    init(_ authorization: HKAuthorizationRequestStatus) {
        switch authorization {
        case .unknown:
            self = .notDetermined
        case .shouldRequest:
            self = .notDetermined
        case .unnecessary:
            self = .determined
        @unknown default:
            self = .notDetermined
        }
    }
}
