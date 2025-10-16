//
//  LastManualBolus.swift
//  Loop
//
//  Created by Pete Schwamb on 10/10/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

public struct LastManualBolus: RawRepresentable {
    public typealias RawValue = [String: Any]

    public let amount: Double
    public let startDate: Date

    public init (amount: Double, startDate: Date) {
        self.amount = amount
        self.startDate = startDate
    }

    public init?(rawValue: RawValue) {
        guard let amount = rawValue["amount"] as? Double,
              let startDate = rawValue["startDate"] as? Date else {
            return nil
        }
        self.amount = amount
        self.startDate = startDate
    }

    public var rawValue: [String : Any] {
        ["amount": amount, "startDate": startDate]
    }
}
