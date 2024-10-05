//
//  Character+IsEmoji.swift
//  Loop
//
//  Created by Noah Brauner on 8/6/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation

extension Character {
    public var isEmoji: Bool {
        unicodeScalars.contains(where: { $0.properties.isEmoji })
    }
}
