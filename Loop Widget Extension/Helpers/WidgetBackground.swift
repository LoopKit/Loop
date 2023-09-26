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
        if #available(watchOS 10.0, iOSApplicationExtension 17.0, iOS 17.0, macOSApplicationExtension 14.0, *) {
            self.containerBackground(for: .widget) { Color("WidgetBackground") }
        } else {
            self.background { Color("WidgetBackground") }
        }
    }
}
