//
//  ActionButton.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/24/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct ActionButton: View {
    var title: Text
    var color: Color
    var action: () -> Void

    var body: some View {
        Button(action: action, label: {
            title
                .fontWeight(.semibold)
                .animation(nil)
        })
        .buttonStyle(ActionButtonStyle(color: color))
        .animation(.default)
        .frame(height: 40)
    }
}

private struct ActionButtonStyle: ButtonStyle {
    var color: Color
    @Environment(\.sizeClass) private var sizeClass

    func makeBody(configuration: Configuration) -> some View {
        backgroundShape
            .padding(.horizontal, sizeClass.hasRoundedCorners ? 4 : 0)
            .overlay(configuration.label)
            .padding(configuration.isPressed ? 1 : 0)
            .overlay(Color.black.opacity(configuration.isPressed ? 0.35 : 0))
    }

    private var backgroundShape: some View {
        Group {
            if sizeClass.hasRoundedCorners {
                Capsule().fill(color)
            } else {
                RoundedRectangle(cornerRadius: 6).fill(color)
            }
        }
    }
}
