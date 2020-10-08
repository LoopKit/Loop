//
//  AnyTransition.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


extension AnyTransition {
    static var shrinkDownAndFade: AnyTransition {
        AnyTransition
            .move(edge: .bottom)
            .combined(with: .scale(scale: 0, anchor: .bottom))
            .combined(with: .opacity)
    }

    static func moveAndFade(to edge: Edge) -> AnyTransition {
        AnyTransition
            .move(edge: edge)
            .combined(with: .opacity)
    }

    static func fadeIn(after delay: Double, removal: AnyTransition = .opacity) -> AnyTransition {
        .asymmetric(
            insertion: AnyTransition.opacity.animation(Animation.default.delay(delay)),
            removal: removal
        )
    }
}
