//
//  Microbolus.swift
//  LoopCore
//
//  Created by Ivan Valkou on 07.11.2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

public enum Microbolus {
    public struct Settings: Equatable, RawRepresentable {
        public typealias RawValue = [String: Any]

        public var enabled: Bool
        public var enabledWithoutCarbs: Bool
        public var partialApplication: Double
        public var minimumBolusSize: Double
        public var shouldOpenBolusScreen: Bool
        public var disableByOverride: Bool
        public var overrideLowerBound: Double

        public init(
            enabled: Bool = false,
            enabledWithoutCarbs: Bool = false,
            partialApplication: Double = 0.3,
            minimumBolusSize: Double = 0,
            shouldOpenBolusScreen: Bool = false,
            disableByOverride: Bool = false,
            overrideLowerBound: Double = 0
        ) {
            self.enabled = enabled
            self.enabledWithoutCarbs = enabledWithoutCarbs
            self.partialApplication = partialApplication
            self.minimumBolusSize = minimumBolusSize
            self.shouldOpenBolusScreen = shouldOpenBolusScreen
            self.disableByOverride = disableByOverride
            self.overrideLowerBound = overrideLowerBound
        }

        public init?(rawValue: [String : Any]) {
            self = Settings()

            if let enabled = rawValue["enabled"] as? Bool {
                self.enabled = enabled
            }

            if let enabledWithoutCarbs = rawValue["enabledWithoutCarbs"] as? Bool {
                self.enabledWithoutCarbs = enabledWithoutCarbs
            }

            if let partialApplication = rawValue["partialApplication"] as? Double {
                self.partialApplication = partialApplication
            }

            if let minimumBolusSize = rawValue["minimumBolusSize"] as? Double {
                self.minimumBolusSize = minimumBolusSize
            }

            if let shouldOpenBolusScreen = rawValue["shouldOpenBolusScreen"] as? Bool {
                self.shouldOpenBolusScreen = shouldOpenBolusScreen
            }

            if let disableByOverride = rawValue["disableByOverride"] as? Bool {
                self.disableByOverride = disableByOverride
            }

            if let overrideLowerBound = rawValue["overrideLowerBound"] as? Double {
                self.overrideLowerBound = overrideLowerBound
            }
        }

        public var rawValue: [String : Any] {
            [
                "enabled": enabled,
                "enabledWithoutCarbs": enabledWithoutCarbs,
                "partialApplication": partialApplication,
                "minimumBolusSize": minimumBolusSize,
                "shouldOpenBolusScreen": shouldOpenBolusScreen,
                "disableByOverride": disableByOverride,
                "overrideLowerBound": overrideLowerBound
            ]
        }
    }
}

public extension Microbolus {
    struct Event {
        public let date: Date
        public let recommendedAmount: Double
        public let amount: Double
        public let reason: String?

        public static func canceled(date: Date, recommended: Double, reason: String) -> Event {
            Event(date: date, recommendedAmount: recommended, amount: 0, reason: reason)
        }

        public static func failed(date: Date, recommended: Double, error: Error) -> Event {
            Event(date: date, recommendedAmount: recommended, amount: 0, reason: "Failed with error: \(error.localizedDescription)")
        }

        public static func succeeded(date: Date, recommended: Double, amount: Double) -> Event {
            Event(date: date, recommendedAmount: recommended, amount: amount, reason: nil)
        }

        public var description: String {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            let percentFormatter = NumberFormatter()
            percentFormatter.maximumFractionDigits = 2
            percentFormatter.numberStyle = .percent
            let percent = amount/recommendedAmount
            return "At \(timeFormatter.string(from: date)): enacted \(amount) (\(percentFormatter.string(for: percent) ?? "0 %")) of recommended \(recommendedAmount). " 
            + (reason ?? "")
        }

    }
}
