//
//  TherapySettingsExampleView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI

struct TherapySettingsExampleView: View {
    
    @EnvironmentObject var displayGlucosePreference: DisplayGlucosePreference
    
    let title: String
    let basalRate: Double
    let carbRatio: Double
    let isf: Double
    
    let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
    
    private let basalRateFormatter = QuantityFormatter(for: .internationalUnitsPerHour)
    
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 36) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Basal Rate")
                        
                        Text("Carb Ratio")
                        
                        Text("ISF")
                    }
                    .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        if let basalRateValue = basalRateFormatter.string(from: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: basalRate)) {
                            Text(basalRateValue)
                        }
                        
                        Text("\(numberFormatter.string(from: carbRatio) ?? "0") g/U")
                        
                        Text(displayGlucosePreference.format(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: isf)))
                    }
                }
                .font(.subheadline)
            }
        }
    }
}
