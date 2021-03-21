//
//  WatchHistoricalCarbs.swift
//  Loop
//
//  Created by Darin Krauss on 8/14/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

struct WatchHistoricalCarbs {
    let objects: [SyncCarbObject]
}

extension WatchHistoricalCarbs: RawRepresentable {
    typealias RawValue = [String: Any]
    
    init?(rawValue: RawValue) {
        guard let rawObjects = rawValue["o"] as? Data,
            let objects = try? Self.decoder.decode([SyncCarbObject].self, from: rawObjects) else {
                return nil
        }
        self.objects = objects
    }
    
    var rawValue: RawValue {
        guard let rawObjects = try? Self.encoder.encode(objects) else {
            return [:]
        }
        return [
            "o": rawObjects
        ]
    }

    private static var encoder: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }

    private static var decoder: PropertyListDecoder = PropertyListDecoder()
}
