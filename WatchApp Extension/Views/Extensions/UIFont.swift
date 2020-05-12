//
//  UIFont.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/27/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


extension UIFont.TextStyle {
    var swiftUIVariant: Font.TextStyle {
        switch self {
        case .largeTitle:
            return .largeTitle
        case .title1, .title2, .title3:
            return .title
        case .headline:
            return .headline
        case .body:
            return .body
        case .callout:
            return .callout
        case .subheadline:
            return .subheadline
        case .footnote:
            return .footnote
        case .caption1, .caption2:
            return .caption
        default:
            assertionFailure("Unknown text style \(self)")
            return .body
        }
    }
}

