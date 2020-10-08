//
//  CarbAmountInput.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct CarbAmountInput: View {
    @Binding var amount: Int
    var increment: () -> Void
    var decrement: () -> Void

    var body: some View {
        HStack {
            decrementButton
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                CarbAmountLabel(amount: amount, scale: .large)
                GramLabel(scale: .large)
            }
            Spacer()
            incrementButton
        }
    }

    private var decrementButton: some View {
        Button(action: decrement, label: {
            Text(verbatim: "−")
                .font(.system(.body, design: .rounded))
                .bold()
        })
        .buttonStyle(CircularAccessoryButtonStyle(color: .carbs))
    }

    private var incrementButton: some View {
        Button(action: increment, label: {
            Text(verbatim: "+")
                .font(.system(.body, design: .rounded))
                .bold()
        })
        .buttonStyle(CircularAccessoryButtonStyle(color: .carbs))
    }
}
