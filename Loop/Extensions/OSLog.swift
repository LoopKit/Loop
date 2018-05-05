//
//  OSLog.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import os.log


extension OSLog {
    convenience init(category: String) {
        self.init(subsystem: "com.loopkit.Loop", category: category)
    }

    func debug(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .debug, args)
    }

    func info(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .info, args)
    }

    func error(_ message: StaticString, _ args: CVarArg...) {
        log(message, type: .error, args)
    }

    private func log(_ message: StaticString, type: OSLogType, _ args: [CVarArg]) {
        switch args.count {
        case 0:
            os_log(message, log: self, type: type)
        case 1:
            os_log(message, log: self, type: type, args[0])
        case 2:
            os_log(message, log: self, type: type, args[0], args[1])
        case 3:
            os_log(message, log: self, type: type, args[0], args[1], args[2])
        default:
            os_log(message, log: self, type: type, args)
        }
    }
}
