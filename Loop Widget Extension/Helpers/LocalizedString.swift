//
//  LocalizedString.swift
//  Loop Widget Extension
//
//  Created by Bastiaan Verhaar on 25/06/2024.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation

private class FrameworkBundle {
    static let main = Bundle(for: Bootstrap.self)
}

func LocalizedString(_ key: String, tableName: String? = nil, value: String? = nil, comment: String) -> String {
    if let value = value {
        return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, value: value, comment: comment)
    } else {
        return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, comment: comment)
    }
}
