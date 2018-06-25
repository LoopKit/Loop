//
//  AbsorptionTimeType.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/25/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation


enum AbsorptionTimeType {
    case fast
    case medium
    case slow
}


extension AbsorptionTimeType: RawRepresentable {
    typealias RawValue = Int

    init?(rawValue: RawValue) {
        switch rawValue {
        case 0:
            self = .fast
        case 1:
            self = .medium
        case 2:
            self = .slow
        default:
            return nil
        }
    }

    var rawValue: RawValue {
        switch self {
        case .fast:
            return 0
        case .medium:
            return 1
        case .slow:
            return 2
        }
    }
}
