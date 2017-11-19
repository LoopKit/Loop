//
//  WCSession.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import WatchConnectivity


extension WCSession {
    #if swift(>=4)
    static func `default`() -> WCSession {
        return self.default
    }
    #endif
}
