//
//  GramLabel.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/6/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct GramLabel: View {
    var origin: Anchor<CGPoint>?
    var scale: PositionedTextScale

    var body: some View {
        ScalablePositionedText<GramLabelPositionKey>(
            text: Text("g", comment: "Short unit label for gram measurement"),
            scale: scale,
            origin: origin,
            smallTextStyle: .footnote,
            largeTextStyle: .callout,
            design: .rounded,
            weight: .bold
        )
    }
}
