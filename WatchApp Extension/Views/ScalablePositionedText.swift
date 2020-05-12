//
//  ScalablePositionedText.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/6/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


enum PositionedTextScale {
    case small
    case large
}

/// Applies a scale effect between text styles to enable smoothly animated text resizing,
/// while managing positioning and propagation of position up the view hierarchy.
struct ScalablePositionedText<Key: PreferenceKey>: View where Key.Value == Anchor<CGPoint>? {
    var text: Text
    var scale: PositionedTextScale
    var origin: Anchor<CGPoint>?
    var smallTextStyle: UIFont.TextStyle
    var largeTextStyle: UIFont.TextStyle
    var design: Font.Design = .default
    var weight: Font.Weight?

    var body: some View {
        text
            .font(.system(textStyle.swiftUIVariant, design: design))
            .fontWeight(weight)
            .scaleEffect(scaleRatio, anchor: .topLeading)
            .position(at: origin, orPropagateVia: Key.self)
    }

    private var isLayoutOnly: Bool { origin == nil }

    private var textStyle: UIFont.TextStyle {
        if isLayoutOnly {
            switch scale {
            case .small:
                return smallTextStyle
            case .large:
                return largeTextStyle
            }
        } else {
            return largeTextStyle
        }
    }

    private var isScaleEffectApplied: Bool {
        !isLayoutOnly && scale == .small
    }

    private var scaleRatio: CGFloat {
        isScaleEffectApplied ? smallScaleRatio : 1
    }

    private var smallScaleRatio: CGFloat {
        UIFont.preferredFont(forTextStyle: smallTextStyle).pointSize
            / UIFont.preferredFont(forTextStyle: largeTextStyle).pointSize
    }
}
