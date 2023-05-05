//
//  StoredLoopNotRunningNotification.swift
//  LoopCore
//
//  Created by Pete Schwamb on 5/5/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import Foundation

struct StoredLoopNotRunningNotification: Codable {
    var alertAt: Date
    var title: String
    var body: String
    var isCritical: Bool
}

