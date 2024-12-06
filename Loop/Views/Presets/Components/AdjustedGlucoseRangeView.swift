//
//  AdjustedGlucoseRangeView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKitUI
import SwiftUI

struct AdjustedGlucoseRangeView: View {
    
    @EnvironmentObject var displayGlucosePreference: DisplayGlucosePreference

    @State var lowerBound: HKQuantity
    @State var upperBound: HKQuantity
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(UIColor.secondarySystemBackground), lineWidth: 1)
                .frame(maxWidth: .infinity)
            
            VStack(spacing: 0) {
                Text("Adjusted Range")
                    .font(.subheadline)
                    .padding(.bottom, 4)
                
                Group {
                    Text(displayGlucosePreference.format(lowerBound, includeUnit: false)).foregroundColor(.accentColor) +
                    Text("-").foregroundColor(.secondary).fontWeight(.light) +
                    Text(displayGlucosePreference.format(upperBound, includeUnit: false)).foregroundColor(.accentColor)
                }
                .font(.system(size: UIFontMetrics.default.scaledValue(for: 42), weight: .semibold))
  
                Text(displayGlucosePreference.unit.localizedUnitString(in: .medium) ?? displayGlucosePreference.unit.unitString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
        }
    }
}
