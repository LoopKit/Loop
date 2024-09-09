//
//  DeeplinkView.swift
//  Loop Widget Extension
//
//  Created by Noah Brauner on 8/9/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI

fileprivate extension Deeplink {
    var deeplinkURL: URL {
        URL(string: "loop://\(rawValue)")!
    }
    
    var accentColor: Color {
        switch self {
        case .carbEntry:
            return .carbs
        case .bolus:
            return .insulin
        case .preMeal:
            return .carbs
        case .customPresets:
            return .glucose
        }
    }
    
    var icon: Image {
        switch self {
        case .carbEntry:
            return Image(.carbs)
        case .bolus:
            return Image(.bolus)
        case .preMeal:
            return Image(.premeal)
        case .customPresets:
            return Image(.workout)
        }
    }
}

struct DeeplinkView: View {
    let destination: Deeplink
    var isActive: Bool = false
    
    var body: some View {
        Link(destination: destination.deeplinkURL) {
            destination.icon
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .foregroundColor(isActive ? .white : destination.accentColor)
                .containerRelativeBackground(color: isActive ? destination.accentColor : .widgetSecondaryBackground)
        }
    }
}
