//
//  DoseVolumeInput.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct DoseVolumeInput: View {
    var volume: Double
    var unit = Text("U")
    var isEditable: Bool
    var increment: () -> Void
    var decrement: () -> Void
    var formatVolume: (_ volume: Double) -> String

    var body: some View {
        // Negative spacing draws the increment buttons close enough
        // to fit a unit label in the width of a 38mm watch.
        HStack(spacing: -4) {
            if isEditable {
                decrementButton
            }
            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                numericLabel
                unitLabel
            }

            Spacer()
            if isEditable {
                incrementButton
            }
        }
    }

    private var numericLabel: some View {
        Text(formatVolume(volume))
            .font(.system(.title, design: .rounded))
            .bold()
            .foregroundColor(.insulin)
            .fixedSize()
    }

    private var unitLabel: some View {
        unit
            .font(.system(.callout, design: .rounded))
            .bold()
            .foregroundColor(.insulin)
            .fixedSize()
    }

    private var decrementButton: some View {
        Button(action: {
            self.decrement()
            WKInterfaceDevice.current().play(.directionDown)
        }, label: {
            Text(verbatim: "−")
                .font(.system(.body, design: .rounded))
                .bold()
        })
        .buttonStyle(CircularAccessoryButtonStyle(color: .insulin))
        .transition(.opacity)
    }

    private var incrementButton: some View {
        Button(action: {
            self.increment()
            WKInterfaceDevice.current().play(.directionUp)
        }, label: {
            Text(verbatim: "+")
                .font(.system(.body, design: .rounded))
                .bold()
        })
        .buttonStyle(CircularAccessoryButtonStyle(color: .insulin))
        .transition(.opacity)
    }
}
