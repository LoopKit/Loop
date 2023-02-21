//
//  BasalView.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct BasalView: View {
    let netBasal: NetBasalContext
    let isOld: Bool

    
    var body: some View {
        let percent = netBasal.percentage
        let rate = netBasal.rate
        
        VStack(spacing: 1) {
            BasalRateView(percent: percent)
                .overlay(
                    BasalRateView(percent: percent)
                        .stroke(isOld ? Color(UIColor.systemGray3) : Color("insulin"), lineWidth: 2)
                )
                .foregroundColor((isOld ? Color(UIColor.systemGray3) : Color("insulin")).opacity(0.5))
                .frame(width: 44, height: 22)

            if let rateString = decimalFormatter.string(from: NSNumber(value: rate)) {
                Text("\(rateString) U")
                    .font(.footnote)
                    .foregroundColor(Color(isOld ? UIColor.systemGray3 : UIColor.secondaryLabel))
            }
            else {
                Text("-U")
                    .font(.footnote)
                    .foregroundColor(Color(isOld ? UIColor.systemGray3 : UIColor.secondaryLabel))
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

struct BasalRateView: Shape {
    // Needs a basal percentage
    var percent: Double
    
    func path(in rect: CGRect) -> Path {
        let startX = rect.minX
        let endX = rect.maxX
        let midY = rect.midY

        var path = Path()
        path.move(to: CGPoint(x: startX, y: midY))

        let leftAnchor = startX + 1/6 * rect.size.width
        let rightAnchor = startX + 5/6 * rect.size.width

        let yAnchor = rect.midY - CGFloat(percent) * (rect.size.height - 2) / 2

        path.addLine(to: CGPoint(x: leftAnchor, y: midY))
        path.addLine(to: CGPoint(x: leftAnchor, y: yAnchor))
        path.addLine(to: CGPoint(x: rightAnchor, y: yAnchor))
        path.addLine(to: CGPoint(x: rightAnchor, y: midY))
        path.addLine(to: CGPoint(x: endX, y: midY))

        return path
    }
}
