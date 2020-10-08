//
//  CircularAccessoryButtonStyle.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/24/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct CircularAccessoryButtonStyle: ButtonStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        Circle()
            .fill(color.opacity(0.14))
            .overlay(configuration.label.foregroundColor(color))
            .padding(configuration.isPressed ? 1 : 0)
            .frame(width: 22, height: 22)
            .overlay(Color.black.opacity(configuration.isPressed ? 0.35 : 0))
    }
}
