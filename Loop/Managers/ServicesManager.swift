//
//  ServicesManager.swift
//  Loop
//
//  Created by Darin Krauss on 5/22/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI

class ServicesManager {

    private let pluginManager: PluginManager

    let analyticsServicesManager: AnalyticsServicesManager

    let loggingServicesManager: LoggingServicesManager

    let remoteDataServicesManager: RemoteDataServicesManager

    private var services = [Service]()

    private let servicesLock = UnfairLock()

    weak var loopDataManager: LoopDataManager?

    init(
        pluginManager: PluginManager,
        analyticsServicesManager: AnalyticsServicesManager,
        loggingServicesManager: LoggingServicesManager,
        remoteDataServicesManager: RemoteDataServicesManager,
        dataManager: LoopDataManager
    ) {
        self.pluginManager = pluginManager
        self.analyticsServicesManager = analyticsServicesManager
        self.loggingServicesManager = loggingServicesManager
        self.remoteDataServicesManager = remoteDataServicesManager
        self.loopDataManager = dataManager
        
        restoreState()
    }

    public var availableServices: [AvailableService] {
        return pluginManager.availableServices + availableStaticServices
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
        UserDefaults.appGroup?.servicesState = services.compactMap { $0.rawValue }
    }
    
    private func storeSettings(settings: TherapySettings) {
        loopDataManager?.settings.glucoseTargetRangeSchedule = settings.glucoseTargetRangeSchedule
        loopDataManager?.settings.preMealTargetRange = settings.preMealTargetRange
        loopDataManager?.settings.legacyWorkoutTargetRange = settings.workoutTargetRange
        loopDataManager?.settings.suspendThreshold = settings.suspendThreshold
        loopDataManager?.settings.maximumBolus = settings.maximumBolus
        loopDataManager?.settings.maximumBasalRatePerHour = settings.maximumBasalRatePerHour
        loopDataManager?.insulinSensitivitySchedule = settings.insulinSensitivitySchedule
        loopDataManager?.carbRatioSchedule = settings.carbRatioSchedule
        loopDataManager?.basalRateSchedule = settings.basalRateSchedule
        loopDataManager?.insulinModelSettings = settings.insulinModelSettings
    }

    private func restoreState() {
        UserDefaults.appGroup?.servicesState.forEach { rawValue in
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

extension ServicesManager: ServiceDelegate {

    func serviceDidUpdateState(_ service: Service) {
        saveState()
    }

    func serviceHasNewTherapySettings(_ settings: TherapySettings) {
        storeSettings(settings: settings)
    }
}
