//
//  CompletionCheckmark.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct CompletionCheckmark: View {
    var checkmarkColor: Color
    var checkmarkLineWidth: CGFloat = 5
    var circleStrokeColor: Color
    var circleLineWidth: CGFloat = 3

    @State private var appeared = false

    private let checkmarkScale: CGFloat = 0.35

    var body: some View {
        strokedCircle
            .overlay(checkmark)
            .onAppear {
                withAnimation(Animation.default.speed(0.65).delay(0.3)) {
                    self.appeared = true
                }
            }
    }

    private var strokedCircle: some View {
        Circle()
            .rotation(.degrees(-90)) // Start the animation from 12 o'clock
            .trim(from: 0, to: appeared ? 1 : 0)
            .stroke(circleStrokeColor, style: StrokeStyle(lineWidth: circleLineWidth, lineCap: .round))
    }

    private var checkmark: some View {
        Checkmark()
            .stroke(checkmarkColor, style: StrokeStyle(lineWidth: checkmarkLineWidth / checkmarkScale, lineCap: .round, lineJoin: .round))
            .aspectRatio(22.5 / 21.5, contentMode: .fit)
            .scaleEffect(checkmarkScale)
    }
}
