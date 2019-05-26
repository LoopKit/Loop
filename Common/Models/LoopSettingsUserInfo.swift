//
//  LoopSettingsUserInfo.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopCore


struct LoopSettingsUserInfo {
    let settings: LoopSettings
}


extension LoopSettingsUserInfo: RawRepresentable {
    typealias RawValue = [String: Any]

    static let name = "LoopSettingsUserInfo"
    static let version = 1

    init?(rawValue: RawValue) {
        guard rawValue["v"] as? Int == LoopSettingsUserInfo.version,
            rawValue["name"] as? String == LoopSettingsUserInfo.name,
            let settingsRaw = rawValue["s"] as? LoopSettings.RawValue,
            let settings = LoopSettings(rawValue: settingsRaw)
        else {
            return nil
        }

        self.settings = settings
    }

    var rawValue: RawValue {
        return [
            "v": LoopSettingsUserInfo.version,
            "name": LoopSettingsUserInfo.name,
            "s": settings.rawValue
        ]
    }
}
