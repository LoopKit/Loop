//
//  Environment+AppName.swift
//  LoopUI
//
//  Created by Rick Pasetto on 7/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI

private struct AppNameKey: EnvironmentKey {
    static let defaultValue = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
}

public extension EnvironmentValues {
    var appName: String {
        get { self[AppNameKey.self] }
        set { self[AppNameKey.self] = newValue }
    }
}
