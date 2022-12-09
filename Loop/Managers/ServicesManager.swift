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

class ServicesManager {

    private let pluginManager: PluginManager

    let analyticsServicesManager: AnalyticsServicesManager

    let loggingServicesManager: LoggingServicesManager

    let remoteDataServicesManager: RemoteDataServicesManager
    
    private var services = [Service]()

    private let servicesLock = UnfairLock()

    private let log = OSLog(category: "ServicesManager")

    @PersistedProperty(key: "Services")
    var rawServices: [Service.RawValue]?

    init(
        pluginManager: PluginManager,
        analyticsServicesManager: AnalyticsServicesManager,
        loggingServicesManager: LoggingServicesManager,
        remoteDataServicesManager: RemoteDataServicesManager
    ) {
        self.pluginManager = pluginManager
        self.analyticsServicesManager = analyticsServicesManager
        self.loggingServicesManager = loggingServicesManager
        self.remoteDataServicesManager = remoteDataServicesManager
        restoreState()
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

        let result = serviceUIType.setupViewController(colorPalette: .default)
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
}

// MARK: - ServiceDelegate

extension ServicesManager: ServiceDelegate {
    func serviceDidUpdateState(_ service: Service) {
        saveState()
    }

    func serviceWantsDeletion(_ service: Service) {
        log.default("Service with identifier '%{public}@' deleted", service.serviceIdentifier)
        removeActiveService(service)
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
