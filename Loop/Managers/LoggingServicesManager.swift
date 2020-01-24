//
//  LoggingServicesManager.swift
//  Loop
//
//  Created by Darin Krauss on 6/13/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log
import LoopKit

final class LoggingServicesManager: Logging {

    private var loggingServices = [LoggingService]()

    init() {}

    func addService(_ loggingService: LoggingService) {
        loggingServices.append(loggingService)
    }

    func restoreService(_ loggingService: LoggingService) {
        loggingServices.append(loggingService)
    }

    func removeService(_ loggingService: LoggingService) {
        loggingServices.removeAll { $0.serviceIdentifier == loggingService.serviceIdentifier }
    }

    func log (_ message: StaticString, subsystem: String, category: String, type: OSLogType, _ args: [CVarArg]) {
        loggingServices.forEach { $0.log(message, subsystem: subsystem, category: category, type: type, args) }
    }
    
}
