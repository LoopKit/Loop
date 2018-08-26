//
//  LocalizedString.swift
//  LoopUI
//
//  Created by Kathryn DiSimone on 8/15/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation

private class FrameworkBundle {
    static let main = Bundle(for: FrameworkBundle.self)
}

func LocalizedString(_ key: String, tableName: String? = nil, value: String = "", comment: String) -> String {
    return NSLocalizedString(key, tableName: tableName, bundle: FrameworkBundle.main, value: value, comment: comment)
}
