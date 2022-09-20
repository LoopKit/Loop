//
//  GlucoseView.swift
//  Loop
//
//  Created by Noah Brauner on 8/15/22.
//  Copyright © 2022 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKit
import HealthKit

struct GlucoseView: View {
    @Environment(\.sizeCategory) var sizeCategory
    var entry: SmallStatusEntry
    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(spacing: 2) {
                if let quantity = entry.currentGlucose?.quantity,
                   let unit = entry.unit {
                    let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
                    if let glucoseString = numberFormatter.string(from: quantity.doubleValue(for: unit)) {
                        Text(glucoseString)
                            .font(.system(size: 24, weight: .heavy, design: .default))
                    }
                    else {
                        Text("-")
                            .font(.system(size: 24, weight: .heavy, design: .default))
                    }
                }
                else {
                    Text("--")
                        .font(.system(size: 24, weight: .heavy, design: .default))
                }
                
                if let trendImageName = getArrowImage() {
                    Image(systemName: trendImageName)
                }
            }
            // Prevent truncation of text
            .fixedSize(horizontal: true, vertical: false)
            
            let unitString = entry.unit == nil ? "-" : entry.unit!.localizedShortUnitString
            if let previousGlucose = entry.previousGlucose,
               let currentGlucose = entry.currentGlucose,
               let unit = entry.unit {
                let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
                let deltaString = (previousGlucose.quantity > currentGlucose.quantity ? "-" : "+") + (numberFormatter.string(from: abs(previousGlucose.quantity.doubleValue(for: unit) - currentGlucose.quantity.doubleValue(for: unit))) ?? "")
                
                Text(deltaString + " " + unitString)
                // Dynamic text causes string to be cut off
                    .font(.system(size: 11))
                    .foregroundColor(entry.isOld ? Color(UIColor.systemGray3) : Color(UIColor.secondaryLabel))
            }
            else {
                Text(unitString)
                    .font(.caption2)
                    .foregroundColor(entry.isOld ? Color(UIColor.systemGray3) : Color(UIColor.secondaryLabel))
            }
        }
    }
    
    private func getArrowImage() -> String? {
        switch entry.sensor?.trendType {
        case .upUpUp:
            return "arrow.double.up.circle"
        case .upUp:
            return "arrow.up.circle"
        case .up:
            return "arrow.up.right.circle"
        case .flat:
            return "arrow.right.circle"
        case .down:
            return "arrow.down.right.circle"
        case .downDown:
            return "arrow.down.circle"
        case .downDownDown:
            return "arrow.double.down.circle"
        case .none:
            return nil
        }
    }
}
