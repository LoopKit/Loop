//
//  CarbAmountLabel.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/6/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


struct CarbAmountLabel: View {
    var amount: Int
    var origin: Anchor<CGPoint>?
    var scale: PositionedTextScale

    var body: some View {
        ScalablePositionedText<CarbAmountPositionKey>(
            text: Text(verbatim: "\(amount)"),
            scale: scale,
            origin: origin,
            smallTextStyle: .body,
            largeTextStyle: .title1,
            design: .rounded,
            weight: .bold
        )
    }
}
