//
//  BolusArrow.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct BolusArrow: View {
    var progress: Double
    @Environment(\.sizeClass) private var sizeClass

    private var isFinished: Bool { progress >= 1.0 }

    private let triangleSize = CGSize(width: 31, height: 25)
    private let triangleOffsetY: CGFloat = 17

    var body: some View {
        ZStack {
            arrow
                .alignmentGuide(VerticalAlignment.center) { dimensions in
                    dimensions[VerticalAlignment.center]
                        - self.triangleOffsetY
                        + CGFloat(self.progress) * self.triangleOffsetY
                }
            arrow
        }
        .padding(.top, 4)
        // Animate the arrow down off-screen once finished
        .offset(y: isFinished ? sizeClass.screenSize.height : 0)
        .animation(Animation.default.speed(isFinished ? 0.35 : 1.0))
    }

    private var arrow: some View {
        Arrow(fillOpacity: progress)
            .frame(width: triangleSize.width, height: triangleSize.height)
    }
}

private struct Arrow: View {
    var fillOpacity: Double

    var body: some View {
        ZStack {
            TopDownTriangle().fill(Color.black)
            TopDownTriangle().fill(Color.insulin.opacity(fillOpacity))
            TopDownTriangle().stroke(Color.insulin, lineWidth: 3)
        }
    }
}
