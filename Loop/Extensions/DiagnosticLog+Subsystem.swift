//
//  DiagnosticLog+Subsystem.swift
//  Loop
//
//  Created by Darin Krauss on 6/12/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit

extension DiagnosticLog {

    convenience init(category: String) {
        self.init(subsystem: "com.loopkit.Loop", category: category)
    }

}
