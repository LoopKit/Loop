//
//  LocalizedString.swift
//  LoopUI
//
//  Created by Kathryn DiSimone on 8/15/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

func LocalizedString(_ key: String, tableName: String? = nil, value: String? = nil, comment: String) -> String {
    if let value = value {
        return NSLocalizedString(key, tableName: tableName, bundle: Bundle.module, value: value, comment: comment)
    } else {
        return NSLocalizedString(key, tableName: tableName, bundle: Bundle.module, comment: comment)
    }
}
