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
        public var safeMode: SafeMode
        public var minimumBolusSize: Double
        public var shouldOpenBolusScreen: Bool

        public init(
            enabled: Bool = false,
            size: Double = 30,
            enabledWithoutCarbs: Bool = false,
            sizeWithoutCarb: Double = 30,
            safeMode: SafeMode = .enabled,
            minimumBolusSize: Double = 0,
            shouldOpenBolusScreen: Bool = false
        ) {
            self.enabled = enabled
            self.size = size
            self.enabledWithoutCarbs = enabledWithoutCarbs
            self.sizeWithoutCarbs = sizeWithoutCarb
            self.safeMode = safeMode
            self.minimumBolusSize = minimumBolusSize
            self.shouldOpenBolusScreen = shouldOpenBolusScreen
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
        }

        public var rawValue: [String : Any] {
            [
                "enabled": enabled,
                "size": size,
                "enabledWithoutCarbs": enabledWithoutCarbs,
                "sizeWithoutCarbs": sizeWithoutCarbs,
                "safeMode": safeMode.rawValue,
                "minimumBolusSize": minimumBolusSize,
                "shouldOpenBolusScreen": shouldOpenBolusScreen
            ]
        }
    }
}
