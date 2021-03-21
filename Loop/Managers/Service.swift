//
//  Service.swift
//  Loop
//
//  Created by Darin Krauss on 5/17/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import MockKit

let staticServices: [Service.Type] = [MockService.self]

let staticServicesByIdentifier: [String: Service.Type] = staticServices.reduce(into: [:]) { (map, Type) in
    map[Type.serviceIdentifier] = Type
}

let availableStaticServices = staticServices.map { (Type) -> AvailableService in
    return AvailableService(identifier: Type.serviceIdentifier, localizedTitle: Type.localizedTitle, providesOnboarding: false)
}

func ServiceFromRawValue(_ rawValue: [String: Any]) -> Service? {
    guard let serviceIdentifier = rawValue["serviceIdentifier"] as? String,
        let rawState = rawValue["state"] as? Service.RawStateValue,
        let ServiceType = staticServicesByIdentifier[serviceIdentifier]
    else {
        return nil
    }

    return ServiceType.init(rawState: rawState)
}

extension Service {

    var rawValue: RawStateValue {
        return [
            "serviceIdentifier": serviceIdentifier,
            "state": rawState
        ]
    }

}
