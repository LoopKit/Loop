//
//  WidgetBackground.swift
//  Loop Widget Extension
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI

extension View {
    @ViewBuilder
    func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) {
                background { Color.widgetBackground }
            }
        } else {
            background { Color.widgetBackground }
        }
    }
    
    @ViewBuilder
    func containerRelativeBackground(color: Color = .widgetSecondaryBackground) -> some View {
        background(
            ContainerRelativeShape()
                .fill(color)
        )
    }
}
