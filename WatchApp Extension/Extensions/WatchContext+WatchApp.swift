//
//  WatchContext.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/16/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopAlgorithm
import LoopKit

extension WatchContext {
    var activeInsulin: LoopQuantity? {
        guard let value = iob else {
            return nil
        }

        return LoopQuantity(unit: .internationalUnit, doubleValue: value)
    }

    var activeCarbohydrates: LoopQuantity? {
        guard let value = cob else {
            return nil
        }

        return LoopQuantity(unit: .gram, doubleValue: value)
    }

    var reservoirVolume: LoopQuantity? {
        guard let value = reservoir else {
            return nil
        }

        return LoopQuantity(unit: .internationalUnit, doubleValue: value)
    }
}
