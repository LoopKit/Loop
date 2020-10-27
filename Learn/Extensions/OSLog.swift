//
//  OSLog.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log


extension OSLog {
    convenience init(category: String) {
        self.init(subsystem: "com.loopkit.Learn", category: category)
    }
}
