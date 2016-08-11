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

    init(recommendedBolus: Double) {
        self.recommendedBolus = recommendedBolus
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
    }

    var rawValue: RawValue {
        return [
            "v": self.dynamicType.version,
            "name": BolusSuggestionUserInfo.name,
            "br": recommendedBolus
        ]
    }
}
