//
//  GramLabelPositionKey.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct GramLabelPositionKey: PreferenceKey {
    static var defaultValue: Anchor<CGPoint>? { nil }

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}
