//
//  Service.swift
//  Loop
//
//  Created by Darin Krauss on 5/17/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopKit
import MockKit

extension Service {

    var rawValue: RawStateValue {
        return [
            "serviceIdentifier": serviceIdentifier,
            "state": rawState
        ]
    }

}
