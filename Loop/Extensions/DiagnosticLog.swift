//
//  DiagnosticLog.swift
//  LoopKit
//
//  Created by Darin Krauss on 6/12/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log

public class DiagnosticLog {

    private let subsystem: String

    private let category: String

    private let log: OSLog

    public init(subsystem: String, category: String) {
        self.subsystem = subsystem
        self.category = category
        self.log = OSLog(subsystem: subsystem, category: category)
    }

    public func debug(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .debug, args)
    }

    public func info(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .info, args)
    }

    public func `default`(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .default, args)
    }

    public func error(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .error, args)
    }

    private func log(_ message: StaticString, type: OSLogType, _ args: [CVarArg]) {
        switch args.count {
        case 0:
            os_log(message, log: log, type: type)
        case 1:
            os_log(message, log: log, type: type, args[0])
        case 2:
            os_log(message, log: log, type: type, args[0], args[1])
        case 3:
            os_log(message, log: log, type: type, args[0], args[1], args[2])
        case 4:
            os_log(message, log: log, type: type, args[0], args[1], args[2], args[3])
        case 5:
            os_log(message, log: log, type: type, args[0], args[1], args[2], args[3], args[4])
        default:
            os_log(message, log: log, type: type, args)
        }

        guard let sharedLogging = SharedLogging.instance else {
            return
        }
        sharedLogging.log(message, subsystem: subsystem, category: category, type: type, args)
    }

}
