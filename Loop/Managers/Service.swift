//
//  Service.swift
//  Loop
//
//  Created by Darin Krauss on 5/17/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import MockKit

let staticServices: [Service.Type] = [MockService.self]

let staticServicesByIdentifier: [String: Service.Type] = [
    MockService.serviceIdentifier: MockService.self
]

var availableStaticServices: [ServiceDescriptor] {
    if FeatureFlags.allowSimulators {
        return [
            ServiceDescriptor(identifier: MockService.serviceIdentifier, localizedTitle: MockService.localizedTitle)
        ]
    } else {
        return []
    }
}
