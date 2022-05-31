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

let staticServicesByIdentifier: [String: Service.Type] = staticServices.reduce(into: [:]) { (map, Type) in
    map[Type.serviceIdentifier] = Type
}

let availableStaticServices = staticServices.map { (Type) -> ServiceDescriptor in
    return ServiceDescriptor(identifier: Type.serviceIdentifier, localizedTitle: Type.localizedTitle)
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

    typealias RawValue = [String: Any]

    var rawValue: RawValue {
        return [
            "serviceIdentifier": serviceIdentifier,
            "state": rawState
        ]
    }

}
