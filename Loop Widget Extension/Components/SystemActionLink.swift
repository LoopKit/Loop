//
//  SystemActionLink.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

struct SystemActionLink: View {
    enum Destination: String, CaseIterable {
        case carbEntry = "carb-entry"
        case bolus = "manual-bolus"
        case preMeal = "pre-meal-preset"
        case customPreset = "custom-presets"
        
        var deeplink: URL {
            URL(string: "loop://\(rawValue)")!
        }
    }
    
    let destination: Destination
    let active: Bool
    
    init(to destination: Destination, active: Bool = false) {
        self.destination = destination
        self.active = active
    }
    
    private func foregroundColor(active: Bool) -> Color {
        switch destination {
        case .carbEntry:
            return Color("fresh")
        case .bolus:
            return Color("insulin")
        case .preMeal:
            return active ? .white : Color("fresh")
        case .customPreset:
            return active ? .white : Color("glucose")
        }
    }
    
    private func backgroundColor(active: Bool) -> Color {
        switch destination {
        case .carbEntry:
            return active ? Color("fresh") : Color("WidgetSecondaryBackground")
        case .bolus:
            return active ? Color("insulin") : Color("WidgetSecondaryBackground")
        case .preMeal:
            return active ? Color("fresh") : Color("WidgetSecondaryBackground")
        case .customPreset:
            return active ? Color("glucose") : Color("WidgetSecondaryBackground")
        }
    }
    
    private var icon: Image {
        switch destination {
        case .carbEntry:
            return Image("carbs")
        case .bolus:
            return Image("bolus")
        case .preMeal:
            return Image("premeal")
        case .customPreset:
            return Image("workout")
        }
    }
    
    var body: some View {
        Link(destination: destination.deeplink) {
            icon
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .foregroundColor(foregroundColor(active: active))
                .background(
                    ContainerRelativeShape()
                        .fill(backgroundColor(active: active))
                )
        }
    }
}
