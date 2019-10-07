//
//  Service.swift
//  Loop
//
//  Created by Darin Krauss on 5/17/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import MockKit
import AmplitudeServiceKit
import LogglyServiceKit
import NightscoutServiceKit

/// The order here specifies the order in the service selection popup
#if DEBUG
let serviceTypes: [Service.Type] = [
    NightscoutService.self,
    LogglyService.self,
    AmplitudeService.self,
    MockService.self,
]
#else
let serviceTypes: [Service.Type] = [
    NightscoutService.self,
    LogglyService.self,
    AmplitudeService.self,
]
#endif

private let serviceTypesByIdentifier: [String: Service.Type] = serviceTypes.reduce(into: [:]) { (map, Type) in
    map[Type.serviceIdentifier] = Type
}

func ServiceFromRawValue(_ rawValue: [String: Any]) -> Service? {
    guard let serviceIdentifier = rawValue["serviceIdentifier"] as? String,
        let rawState = rawValue["state"] as? Service.RawStateValue,
        let serviceType = serviceTypesByIdentifier[serviceIdentifier]
    else {
        return nil
    }

    return serviceType.init(rawState: rawState)
}

extension Service {

    var rawValue: RawStateValue {
        return [
            "serviceIdentifier": serviceIdentifier,
            "state": rawState
        ]
    }

}
