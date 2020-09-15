//
//  View+Position.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/6/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


extension View {
    /// Positions the view at the given anchor if non-nil;
    /// otherwise propagates the view's origin via the given preference key.
    func position<Key: PreferenceKey>(
        at origin: Anchor<CGPoint>?,
        orPropagateVia _: Key.Type,
        visibleWhenPropagatingBounds: Bool = false
    ) -> some View where Key.Value == Anchor<CGPoint>? {
        Group {
            if origin != nil {
                GeometryReader { geometry in
                    self.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .offset(x: geometry[origin!].x, y: geometry[origin!].y)
                }
            } else {
                anchorPreference(key: Key.self, value: .topLeading) { $0 }
                    .opacity(visibleWhenPropagatingBounds ? 1 : 0)
            }
        }
    }
}
