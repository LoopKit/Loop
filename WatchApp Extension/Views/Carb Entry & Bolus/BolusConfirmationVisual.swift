//
//  BolusConfirmationVisual.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct BolusConfirmationVisual: View {
    var progress: Double

    private var isFinished: Bool { progress >= 1.0 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.darkInsulin)
                .opacity(isFinished ? 0 : 1)
                .animation(Animation.default.speed(0.5))
                .overlay(BolusArrow(progress: progress))

            if isFinished {
                CompletionCheckmark(checkmarkColor: .white, circleStrokeColor: .insulin)
                    .padding()
                    .transition(.opacity)
            }
        }.frame(height: 68)
    }
}

struct BolusConfirmationVisual_Previews: PreviewProvider {
    static var previews: some View {
        BolusConfirmationVisual(progress: 0)
    }
}
