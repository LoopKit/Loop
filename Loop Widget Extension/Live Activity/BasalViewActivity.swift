//
//  BasalView.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct BasalViewActivity: View {
    let percent: Double
    let rate: Double
    
    var body: some View {        
        VStack(spacing: 1) {
            BasalRateView(percent: percent)
                .overlay(
                    BasalRateView(percent: percent)
                        .stroke(Color("insulin"), lineWidth: 2)
                )
                .foregroundColor(Color("insulin").opacity(0.5))
                .frame(width: 44, height: 22)

            if let rateString = decimalFormatter.string(from: NSNumber(value: rate)) {
                Text("\(rateString)U")
                    .font(.subheadline)
            }
            else {
                Text("-U")
                    .font(.subheadline)
            }
        }
    }
    
    private let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.minimumIntegerDigits = 1
        formatter.positiveFormat = "+0.0##"
        formatter.negativeFormat = "-0.0##"

        return formatter
    }()
}
