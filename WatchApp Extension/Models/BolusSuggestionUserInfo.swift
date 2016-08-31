//
//  BolusSuggestionUserInfo.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


final class BolusSuggestionUserInfo: RawRepresentable {
    let recommendedBolus: Double
    let maxBolus: Double?

    init(recommendedBolus: Double, maxBolus: Double? = nil) {
        self.recommendedBolus = recommendedBolus
        self.maxBolus = maxBolus
    }

    // MARK: - RawRepresentable
    typealias RawValue = [String: AnyObject]

    static let version = 1
    static let name = "BolusSuggestionUserInfo"

    required init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == self.dynamicType.version && rawValue["name"] as? String == BolusSuggestionUserInfo.name,
            let recommendedBolus = rawValue["br"] as? Double else
        {
            return nil
        }

        self.recommendedBolus = recommendedBolus
        self.maxBolus = rawValue["mb"] as? Double
    }

    var rawValue: RawValue {
        var raw: RawValue = [
            "v": self.dynamicType.version,
            "name": BolusSuggestionUserInfo.name,
            "br": recommendedBolus
        ]

        if let maxBolus = maxBolus {
            raw["mb"] = maxBolus
        }

        return raw
    }
}
