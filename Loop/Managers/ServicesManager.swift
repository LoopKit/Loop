//
//  ServicesManager.swift
//  Loop
//
//  Created by Darin Krauss on 5/22/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log
import LoopKit
import LoopKitUI
import LoopCore
import Combine

class ServicesManager {

    private let pluginManager: PluginManager

    private let alertManager: AlertManager

    let analyticsServicesManager: AnalyticsServicesManager

    let loggingServicesManager: LoggingServicesManager

    let remoteDataServicesManager: RemoteDataServicesManager
    
    weak var servicesManagerDelegate: ServicesManagerDelegate?
    
    private var services = [Service]()

    private let servicesLock = UnfairLock()

    private let log = OSLog(category: "ServicesManager")
    
    lazy private var cancellables = Set<AnyCancellable>()

    @PersistedProperty(key: "Services")
    var rawServices: [Service.RawValue]?

    init(
        pluginManager: PluginManager,
        alertManager: AlertManager,
        analyticsServicesManager: AnalyticsServicesManager,
        loggingServicesManager: LoggingServicesManager,
        remoteDataServicesManager: RemoteDataServicesManager,
        servicesManagerDelegate: ServicesManagerDelegate
    ) {
        self.pluginManager = pluginManager
        self.alertManager = alertManager
        self.analyticsServicesManager = analyticsServicesManager
        self.loggingServicesManager = loggingServicesManager
        self.remoteDataServicesManager = remoteDataServicesManager
        self.servicesManagerDelegate = servicesManagerDelegate
        restoreState()
        
        NotificationCenter.default
            .publisher(for: .LoopDataUpdated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let rawContext = note.userInfo?[LoopDataManager.LoopUpdateContextKey] as? LoopDataManager.LoopUpdateContext.RawValue else {
                    return
                }
                let context = LoopDataManager.LoopUpdateContext(rawValue: rawContext)
                if case context = LoopDataManager.LoopUpdateContext.loopFinished {
                    self?.processPendingRemoteCommands()
                }
            }
            .store(in: &cancellables)
    }

    public var availableServices: [ServiceDescriptor] {
        return pluginManager.availableServices + availableStaticServices
    }

    func setupService(withIdentifier identifier: String) -> Swift.Result<SetupUIResult<ServiceViewController, Service>, Error> {
        switch setupServiceUI(withIdentifier: identifier) {
        case .failure(let error):
            return .failure(error)
        case .success(let success):
            switch success {
            case .userInteractionRequired(let viewController):
                return .success(.userInteractionRequired(viewController))
            case .createdAndOnboarded(let serviceUI):
                return .success(.createdAndOnboarded(serviceUI))
            }
        }
    }

    struct UnknownServiceIdentifierError: Error {}
    
    fileprivate func setupServiceUI(withIdentifier identifier: String) -> Swift.Result<SetupUIResult<ServiceViewController, ServiceUI>, Error> {
        guard let serviceUIType = serviceUITypeByIdentifier(identifier) else {
            return .failure(UnknownServiceIdentifierError())
        }

        let result = serviceUIType.setupViewController(colorPalette: .default, pluginHost: self)
        if case .createdAndOnboarded(let serviceUI) = result {
            serviceOnboarding(didCreateService: serviceUI)
            serviceOnboarding(didOnboardService: serviceUI)
        }

        return .success(result)
    }

    func serviceUITypeByIdentifier(_ identifier: String) -> ServiceUI.Type? {
        return pluginManager.getServiceTypeByIdentifier(identifier) ?? staticServicesByIdentifier[identifier] as? ServiceUI.Type
    }

    private func serviceTypeFromRawValue(_ rawValue: Service.RawStateValue) -> Service.Type? {
        guard let identifier = rawValue["serviceIdentifier"] as? String else {
            return nil
        }

        return serviceUITypeByIdentifier(identifier)
    }

    private func serviceFromRawValue(_ rawValue: Service.RawStateValue) -> Service? {
        guard let serviceType = serviceTypeFromRawValue(rawValue),
            let rawState = rawValue["state"] as? Service.RawStateValue
            else {
                return nil
        }

        return serviceType.init(rawState: rawState)
    }

    public var activeServices: [Service] {
        return servicesLock.withLock { services }
    }

    public func addActiveService(_ service: Service) {
        servicesLock.withLock {
            service.serviceDelegate = self

            services.append(service)

            if let analyticsService = service as? AnalyticsService {
                analyticsServicesManager.addService(analyticsService)
            }
            if let loggingService = service as? LoggingService {
                loggingServicesManager.addService(loggingService)
            }
            if let remoteDataService = service as? RemoteDataService {
                remoteDataServicesManager.addService(remoteDataService)
            }

            saveState()
        }
    }

    public func removeActiveService(_ service: Service) {
        servicesLock.withLock {
            if let remoteDataService = service as? RemoteDataService {
                remoteDataServicesManager.removeService(remoteDataService)
            }
            if let loggingService = service as? LoggingService {
                loggingServicesManager.removeService(loggingService)
            }
            if let analyticsService = service as? AnalyticsService {
                analyticsServicesManager.removeService(analyticsService)
            }

            services.removeAll { $0.serviceIdentifier == service.serviceIdentifier }

            service.serviceDelegate = nil

            saveState()
        }
    }

    private func saveState() {
        rawServices = services.compactMap { $0.rawValue }
        UserDefaults.appGroup?.clearLegacyServicesState()
    }

    private func restoreState() {
        let rawServices = rawServices ?? UserDefaults.appGroup?.legacyServicesState ?? []
        rawServices.forEach { rawValue in
            if let service = serviceFromRawValue(rawValue) {
                service.serviceDelegate = self

                services.append(service)

                if let analyticsService = service as? AnalyticsService {
                    analyticsServicesManager.restoreService(analyticsService)
                }
                if let loggingService = service as? LoggingService {
                    loggingServicesManager.restoreService(loggingService)
                }
                if let remoteDataService = service as? RemoteDataService {
                    remoteDataServicesManager.restoreService(remoteDataService)
                }
            }
        }
    }
    
    func handleRemoteNotification(_ notification: [String: AnyObject]) {
        Task {
            log.default("Remote Notification: Handling notification %{public}@", notification)
            
            guard FeatureFlags.remoteCommandsEnabled else {
                log.error("Remote Notification: Remote Commands not enabled.")
                return
            }
            
            let backgroundTask = await beginBackgroundTask(name: "Handle Remote Notification")
            do {
                try await remoteDataServicesManager.remoteNotificationWasReceived(notification)
            } catch {
                log.error("Remote Notification: Error: %{public}@", String(describing: error))
            }
            
            await endBackgroundTask(backgroundTask)
            log.default("Remote Notification: Finished handling")
        }
    }
    
    func processPendingRemoteCommands() {
        Task {
            guard FeatureFlags.remoteCommandsEnabled else {
                return
            }
            
            let backgroundTask = await beginBackgroundTask(name: "Handle Pending Remote Commands")
            await remoteDataServicesManager.processPendingRemoteCommands()
            await endBackgroundTask(backgroundTask)
        }
    }
    
    private func beginBackgroundTask(name: String) async -> UIBackgroundTaskIdentifier? {
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
    
    private func endBackgroundTask(_ backgroundTask: UIBackgroundTaskIdentifier?) async {
        guard let backgroundTask else {return}
        await UIApplication.shared.endBackgroundTask(backgroundTask)
    }
}

public protocol ServicesManagerDelegate: AnyObject {
    func updateOverrideSetting(name: String, durationTime: TimeInterval?, remoteAddress: String) async throws
    func cancelCurrentOverride() async throws
    func deliverCarbs(amountInGrams: Double, absorptionTime: TimeInterval?, foodType: String?, startDate: Date?) async throws
    func deliverBolus(amountInUnits: Double) async throws
    func updateClosedLoopSetting(activate: Bool) async throws
    func updateAutobolusSetting(activate: Bool) async throws
}

// MARK: - ServiceDelegate

extension ServicesManager: ServiceDelegate {
    var hostIdentifier: String {
        return "com.loopkit.Loop"
    }

    var hostVersion: String {
        var semanticVersion = Bundle.main.shortVersionString

        while semanticVersion.split(separator: ".").count < 3 {
            semanticVersion += ".0"
        }

        semanticVersion += "+\(Bundle.main.version)"

        return semanticVersion
    }

    func serviceDidUpdateState(_ service: Service) {
        saveState()
    }

    func serviceWantsDeletion(_ service: Service) {
        log.default("Service with identifier '%{public}@' deleted", service.serviceIdentifier)
        removeActiveService(service)
    }
    
    func updateRemoteOverride(name: String, durationTime: TimeInterval?, remoteAddress: String) async throws {
        try await servicesManagerDelegate?.updateOverrideSetting(name: name, durationTime: durationTime, remoteAddress: remoteAddress)
    }
    
    func cancelRemoteOverride() async throws {
        try await servicesManagerDelegate?.cancelCurrentOverride()
    }
    
    func deliverRemoteCarbs(amountInGrams: Double, absorptionTime: TimeInterval?, foodType: String?, startDate: Date?) async throws {
        do {
            try await servicesManagerDelegate?.deliverCarbs(amountInGrams: amountInGrams, absorptionTime: absorptionTime, foodType: foodType, startDate: startDate)
            await NotificationManager.sendRemoteCarbEntryNotification(amountInGrams: amountInGrams)
        } catch {
            await NotificationManager.sendRemoteCarbEntryFailureNotification(for: error, amountInGrams: amountInGrams)
            throw error
        }
    }
    
    func deliverRemoteBolus(amountInUnits: Double) async throws {
        do {
            try await servicesManagerDelegate?.deliverBolus(amountInUnits: amountInUnits)
            await NotificationManager.sendRemoteBolusNotification(amount: amountInUnits)
        } catch {
            await NotificationManager.sendRemoteBolusFailureNotification(for: error, amountInUnits: amountInUnits)
            throw error
        }
    }
    
    func updateRemoteClosedLoop(activate: Bool) async throws {
        try await servicesManagerDelegate?.updateClosedLoopSetting(activate: activate)
    }
    
    func updateRemoteAutobolus(activate: Bool) async throws {
        try await servicesManagerDelegate?.updateAutobolusSetting(activate: activate)
    }
}

extension ServicesManager: AlertIssuer {
    func issueAlert(_ alert: Alert) {
        alertManager.issueAlert(alert)
    }

    func retractAlert(identifier: Alert.Identifier) {
        alertManager.retractAlert(identifier: identifier)
    }
}

// MARK: - ServiceOnboardingDelegate

extension ServicesManager: ServiceOnboardingDelegate {
    func serviceOnboarding(didCreateService service: Service) {
        log.default("Service with identifier '%{public}@' created", service.serviceIdentifier)
        addActiveService(service)
    }

    func serviceOnboarding(didOnboardService service: Service) {
        precondition(service.isOnboarded)
        log.default("Service with identifier '%{public}@' onboarded", service.serviceIdentifier)
    }
}

extension ServicesManager {
    var availableSupports: [SupportUI] { activeServices.compactMap { $0 as? SupportUI } }
}
