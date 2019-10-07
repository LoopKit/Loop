//
//  LoggingServicesManager.swift
//  Loop
//
//  Created by Darin Krauss on 6/13/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//


import os.log
import LoopKit

final class LoggingServicesManager: LoggingService {

    private var loggingServices: [LoggingService]!

    init(servicesManager: ServicesManager) {
        self.loggingServices = filter(services: servicesManager.services)
        
        servicesManager.addObserver(self)
    }

    private func filter(services: [Service]) -> [LoggingService] {
        return services.compactMap({ $0 as? LoggingService })
    }

    func log (_ message: StaticString, subsystem: String, category: String, type: OSLogType, _ args: [CVarArg]) {
        loggingServices.forEach { $0.log(message, subsystem: subsystem, category: category, type: type, args) }
    }
}

extension LoggingServicesManager: ServicesManagerObserver {

    func servicesManagerDidUpdate(services: [Service]) {
        loggingServices = filter(services: services)
    }

}
