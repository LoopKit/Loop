//
//  Microbolus.swift
//  LoopCore
//
//  Created by Ivan Valkou on 07.11.2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

public enum Microbolus {
    public enum SafeMode: Int, CaseIterable {
        case enabled
        case limited
        case disabled

        public static var allCases: [SafeMode] {
            [.enabled, .limited, .disabled]
        }
    }

    public struct Settings: Equatable, RawRepresentable {
        public typealias RawValue = [String: Any]

        public var enabled: Bool
        public var size: Double
        public var enabledWithoutCarbs: Bool
        public var sizeWithoutCarbs: Double
        public var partialApplication: Double
        public var safeMode: SafeMode
        public var minimumBolusSize: Double
        public var shouldOpenBolusScreen: Bool
        public var disableByOverride: Bool
        public var overrideLowerBound: Double

        public init(
            enabled: Bool = false,
            size: Double = 30,
            enabledWithoutCarbs: Bool = false,
            sizeWithoutCarb: Double = 30,
            partialApplication: Double = 0.3,
            safeMode: SafeMode = .enabled,
            minimumBolusSize: Double = 0,
            shouldOpenBolusScreen: Bool = false,
            disableByOverride: Bool = false,
            overrideLowerBound: Double = 0
        ) {
            self.enabled = enabled
            self.size = size
            self.enabledWithoutCarbs = enabledWithoutCarbs
            self.sizeWithoutCarbs = sizeWithoutCarb
            self.partialApplication = partialApplication
            self.safeMode = safeMode
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

            if let size = rawValue["size"] as? Double {
                self.size = size
            }

            if let enabledWithoutCarbs = rawValue["enabledWithoutCarbs"] as? Bool {
                self.enabledWithoutCarbs = enabledWithoutCarbs
            }

            if let sizeWithoutCarb = rawValue["sizeWithoutCarbs"] as? Double {
                self.sizeWithoutCarbs = sizeWithoutCarb
            }

            if let partialApplication = rawValue["partialApplication"] as? Double {
                self.partialApplication = partialApplication
            }

            if let safeModeRaw = rawValue["safeMode"] as? Int,
                let safeMode = Microbolus.SafeMode(rawValue: safeModeRaw) {
                self.safeMode = safeMode
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
                "size": size,
                "enabledWithoutCarbs": enabledWithoutCarbs,
                "sizeWithoutCarbs": sizeWithoutCarbs,
                "safeMode": safeMode.rawValue,
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
    }
}
