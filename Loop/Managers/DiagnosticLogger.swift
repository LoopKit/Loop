//
//  DiagnosticLogger.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/10/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation
import os.log
import LoopKit


final class DiagnosticLogger {
    private let isSimulator: Bool = TARGET_OS_SIMULATOR != 0

    var logglyService: LogglyService {
        didSet {
            try! KeychainManager().setLogglyCustomerToken(logglyService.customerToken)
        }
    }

    let remoteLogLevel: OSLogType

    static let shared: DiagnosticLogger = DiagnosticLogger()

    init() {
        remoteLogLevel = isSimulator ? .fault : .info

        // Delete the mLab credentials as they're no longer supported
        try! KeychainManager().setMLabDatabaseName(nil, APIKey: nil)

        let customerToken = KeychainManager().getLogglyCustomerToken()
        logglyService = LogglyService(customerToken: customerToken)
    }

    func forCategory(_ category: String) -> CategoryLogger {
        return CategoryLogger(logger: self, category: category)
    }
}


extension OSLogType {
    fileprivate var tagName: String {
        switch self {
        case let t where t == .info:
            return "info"
        case let t where t == .debug:
            return "debug"
        case let t where t == .error:
            return "error"
        case let t where t == .fault:
            return "fault"
        default:
            return "default"
        }
    }
}


final class CategoryLogger {
    private let logger: DiagnosticLogger
    let category: String

    private let systemLog: OSLog

    fileprivate init(logger: DiagnosticLogger, category: String) {
        self.logger = logger
        self.category = category

        systemLog = OSLog(category: category)
    }

    private func remoteLog(_ type: OSLogType, message: String) {
        guard logger.remoteLogLevel.rawValue <= type.rawValue else {
            return
        }

        logger.logglyService.client?.send(message, tags: [type.tagName, category])
    }

    private func remoteLog(_ type: OSLogType, message: [String: Any]) {
        guard logger.remoteLogLevel.rawValue <= type.rawValue else {
            return
        }

        logger.logglyService.client?.send(message, tags: [type.tagName, category])
    }

    func debug(_ message: [String: Any]) {
        systemLog.debug("%{public}@", String(describing: message))
        remoteLog(.debug, message: message)
    }

    func debug(_ message: String) {
        systemLog.debug("%{public}@", message)
        remoteLog(.debug, message: message)
    }

    func info(_ message: [String: Any]) {
        systemLog.info("%{public}@", String(describing: message))
        remoteLog(.info, message: message)
    }

    func info(_ message: String) {
        systemLog.info("%{public}@", message)
        remoteLog(.info, message: message)
    }

    func `default`(_ message: String) {
        systemLog.info("%{public}@", message)
        remoteLog(.default, message: message)
    }

    func error(_ message: [String: Any]) {
        systemLog.error("%{public}@", String(reflecting: message))
        remoteLog(.error, message: message)
    }

    func error(_ message: String) {
        systemLog.error("%{public}@", message)
        remoteLog(.error, message: message)
    }

    func error(_ error: Error) {
        self.error(String(reflecting: error))
    }
}

