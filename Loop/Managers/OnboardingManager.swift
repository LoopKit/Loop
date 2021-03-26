//
//  OnboardingManager.swift
//  Loop
//
//  Created by Darin Krauss on 2/19/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI

class OnboardingManager {
    private let pluginManager: PluginManager
    private let bluetoothProvider: BluetoothProvider
    private let deviceDataManager: DeviceDataManager
    private let servicesManager: ServicesManager
    private let loopDataManager: LoopDataManager
    private weak var windowProvider: WindowProvider?
    private let userDefaults: UserDefaults

    private var isOnboarded: Bool {
        didSet { userDefaults.onboardingManagerIsOnboarded = isOnboarded }
    }
    private var completedOnboardingIdentifiers: [String] = [] {
        didSet { userDefaults.onboardingManagerCompletedOnboardingIdentifiers = completedOnboardingIdentifiers }
    }
    private var activeOnboarding: OnboardingUI? = nil {
        didSet { userDefaults.onboardingManagerActiveOnboardingRawValue = activeOnboarding?.rawValue }
    }

    private var completion: (() -> Void)?

    init(pluginManager: PluginManager, bluetoothProvider: BluetoothProvider, deviceDataManager: DeviceDataManager, servicesManager: ServicesManager, loopDataManager: LoopDataManager, windowProvider: WindowProvider?, userDefaults: UserDefaults = .standard) {
        self.pluginManager = pluginManager
        self.bluetoothProvider = bluetoothProvider
        self.deviceDataManager = deviceDataManager
        self.servicesManager = servicesManager
        self.loopDataManager = loopDataManager
        self.windowProvider = windowProvider
        self.userDefaults = userDefaults

        self.isOnboarded = userDefaults.onboardingManagerIsOnboarded
        if !isOnboarded {
            self.completedOnboardingIdentifiers = userDefaults.onboardingManagerCompletedOnboardingIdentifiers
            if let activeOnboardingRawValue = userDefaults.onboardingManagerActiveOnboardingRawValue {
                self.activeOnboarding = onboardingFromRawValue(activeOnboardingRawValue)
                self.activeOnboarding?.onboardingDelegate = self
            }
        }
    }

    func onboard(_ completion: @escaping () -> Void) {
        self.completion = completion
        resumeOnboarding()
    }

    private func resumeOnboarding() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !isOnboarded else {
            complete()
            return
        }

        if let onboarding = nextActiveOnboarding {
            displayOnboarding(onboarding)
            return
        }

        ensureAuthorization {
            DispatchQueue.main.async {
                self.isOnboarded = true
                self.complete()
            }
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

    private func displayOnboarding(_ onboarding: OnboardingUI) {
        var onboardingViewController = onboarding.onboardingViewController(onboardingProvider: self, displayGlucoseUnitObservable: deviceDataManager.displayGlucoseUnitObservable, colorPalette: .default)
        onboardingViewController.cgmManagerCreateDelegate = deviceDataManager
        onboardingViewController.cgmManagerOnboardDelegate = deviceDataManager
        onboardingViewController.pumpManagerCreateDelegate = deviceDataManager
        onboardingViewController.pumpManagerOnboardDelegate = deviceDataManager
        onboardingViewController.serviceCreateDelegate = servicesManager
        onboardingViewController.serviceOnboardDelegate = servicesManager
        onboardingViewController.completionDelegate = self

        windowProvider?.window?.rootViewController = onboardingViewController
    }

    private func completeActiveOnboarding() {
        dispatchPrecondition(condition: .onQueue(.main))

        if let activeOnboarding = self.activeOnboarding {
            completedOnboardingIdentifiers.append(activeOnboarding.onboardingIdentifier)
            self.activeOnboarding = nil
        }
        resumeOnboarding()
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

    private func complete() {
        if let completion = completion {
            self.completion = nil
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
        precondition(onboarding === activeOnboarding)
        userDefaults.onboardingManagerActiveOnboardingRawValue = onboarding.rawValue
    }

    func onboarding(_ onboarding: OnboardingUI, hasNewTherapySettings therapySettings: TherapySettings) {
        precondition(onboarding === activeOnboarding)
        loopDataManager.therapySettings = therapySettings
    }

    func onboarding(_ onboarding: OnboardingUI, hasNewDosingEnabled dosingEnabled: Bool) {
        precondition(onboarding === activeOnboarding)
        loopDataManager.settings.dosingEnabled = dosingEnabled
    }
}

// MARK: - CompletionDelegate

extension OnboardingManager: CompletionDelegate {
    func completionNotifyingDidComplete(_ object: CompletionNotifying) {
        DispatchQueue.main.async {
            self.completeActiveOnboarding()
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

    func setupCGMManager(withIdentifier identifier: String) -> Swift.Result<SetupUIResult<UIViewController & CGMManagerCreateNotifying & CGMManagerOnboardNotifying & CompletionNotifying, CGMManager>, Error> {
        return deviceDataManager.setupCGMManager(withIdentifier: identifier)
    }
}

// MARK: - PumpManagerProvider

extension OnboardingManager: PumpManagerProvider {
    var activePumpManager: PumpManager? { deviceDataManager.pumpManager }

    var availablePumpManagers: [PumpManagerDescriptor] { deviceDataManager.availablePumpManagers }

    func setupPumpManager(withIdentifier identifier: String, initialSettings settings: PumpManagerSetupSettings) -> Swift.Result<SetupUIResult<UIViewController & PumpManagerCreateNotifying & PumpManagerOnboardNotifying & CompletionNotifying, PumpManager>, Error> {
        return deviceDataManager.setupPumpManager(withIdentifier: identifier, initialSettings: settings)
    }
}

// MARK: - ServiceProvider

extension OnboardingManager: ServiceProvider {
    var activeServices: [Service] { servicesManager.activeServices }

    var availableServices: [ServiceDescriptor] { servicesManager.availableServices }

    func setupService(withIdentifier identifier: String) -> Swift.Result<SetupUIResult<UIViewController & ServiceCreateNotifying & ServiceOnboardNotifying & CompletionNotifying, Service>, Error> {
        return servicesManager.setupService(withIdentifier: identifier)
    }
}

// MARK: - OnboardingProvider

extension OnboardingManager: OnboardingProvider {
    var allowSkipOnboarding: Bool { FeatureFlags.mockTherapySettingsEnabled }   // NOTE: SKIP ONBOARDING - DEBUG AND TEST ONLY
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

// MARK: - UserDefaults

fileprivate extension UserDefaults {
    private enum Key: String {
        case onboardingManagerIsOnboarded = "com.loopkit.Loop.OnboardingManager.IsOnboarded"
        case onboardingManagerCompletedOnboardingIdentifiers = "com.loopkit.Loop.OnboardingManager.CompletedOnboardingIdentifiers"
        case onboardingManagerActiveOnboardingRawValue = "com.loopkit.Loop.OnboardingManager.ActiveOnboardingRawValue"
    }

    var onboardingManagerIsOnboarded: Bool {
        get { bool(forKey: Key.onboardingManagerIsOnboarded.rawValue) }
        set { set(newValue, forKey: Key.onboardingManagerIsOnboarded.rawValue) }
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
