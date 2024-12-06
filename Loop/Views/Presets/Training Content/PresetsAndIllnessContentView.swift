//
//  PresetsAndIllnessContentView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import SwiftUI

struct PresetsAndIllnessContentView: View {
    
    @Environment(\.appName) private var appName
    @EnvironmentObject var displayGlucosePreference: DisplayGlucosePreference
    
    enum StepNumber {
        case one
        case two
        case three
        case four
    }
    
    let step: StepNumber
    
    var body: some View {
        switch step {
        case .one:
            stepOneView
        case .two:
            stepTwoView
        case .three:
            stepThreeView
        case .four:
            stepFourView
        }
    }
    
    private let lowerBound = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 130)
    private let upperBound = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 140)
    
    private let basalRateFormatter = QuantityFormatter(for: .internationalUnitsPerHour)
    
    @ViewBuilder
    var stepOneView: some View {
        Text("Physical stressors can cause your glucose to rise and sickness is a common example. Your healthcare provider can help you make a personal plan for sickness. The following is one example of using presets to manage an illness.", comment: "Presets and illness training content, paragraph 1")
            .bold()
        
        Text("Let’s imagine Paloma Porpoise notices her glucose is higher than usual and wants to create a preset to help keep her glucose in range while she is sick.", comment: "Presets and illness training content, paragraph 2")
        
        TherapySettingsExampleView(
            title: NSLocalizedString("Paloma’s Therapy Settings", comment: "Presets and illness training content, therapy settings example, title"),
            basalRate: 0.5,
            carbRatio: 13,
            isf: 50
        )
    }
    
    @ViewBuilder
    var stepTwoView: some View {
        Text("Let’s explore each of the configurable settings that will impact Paloma’s insulin delivery.", comment: "Presets and illness training content, paragraph 2")
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Insulin Needs", comment: "Presets and illness training content, overall insulin, subtitle")
                .font(.title2.bold())
            
            if let string = try? AttributedString(markdown: String(format: NSLocalizedString("Paloma wants to tell the %1$@ system that she needs more insulin than usual since her glucose has been elevated. She will adjust her overall insulin **above** her scheduled delivery.", comment: "Presets and illness training content, overall insulin, paragraph 1"), appName)) {
                Text(string)
            }
        }
        
        PercentPickerView(value: .constant(110))
        
        ImpactView {
            if let string = try? AttributedString(markdown: "**Basal** Rate was \(basalRateFormatter.string(from: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: 0.5)) ?? "0") and will be \(basalRateFormatter.string(from: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: 0.6)) ?? "0")\n**Carb Ratio** was 13 g and will be 11.7 g\n**ISF** was \(displayGlucosePreference.format(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 50))) and will be \(displayGlucosePreference.format(HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 45)))", options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(string)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @ViewBuilder
    var stepThreeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Correction Range", comment: "Presets and illness training content, correction range, subtitle")
                .font(.title2.bold())
            
            Text("Paloma’s normal correction range is set to \(displayGlucosePreference.format(lowerQuantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 105), higherQuantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 110))).", comment: "Presets and illness training content, correction range, paragraph 1")
        }
        
        if let string = try? AttributedString(markdown: "In this scenario, Paloma will increase her correction range to **\(displayGlucosePreference.format(lowerQuantity: lowerBound, higherQuantity: upperBound))** to prevent drops due to eating less or not absorbing what she eats while sick.") {
            Text(string)
        }
        
        AdjustedGlucoseRangeView(
            lowerBound: lowerBound,
            upperBound: upperBound
        )
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Duration", comment: "Presets and illness training content, duration, subtitle")
                .font(.title2.bold())
            
            Text(String(format: NSLocalizedString("Paloma will set her preset duration to “Until I Turn Off” since she is not sure when her illness will pass. %1$@ will remind her every 8 hours that the preset is running. ", comment: "Presets and illness training content, duration, paragraph 1"), appName))
        }
    }
    
    @ViewBuilder
    var stepFourView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Impact on Bolusing", comment: "Presets and illness training content, impact on bolusing, subtitle")
                .font(.title2.bold())
            
            Text("Let’s imagine Paloma decides to eat a meal of 31g carbs. How will her preset impact her bolus recommendation?", comment: "Presets and illness training content, impact on bolusing, paragraph 1")
        }
        
        Text("While a preset is ON, the modified basal rates, carb ratio and insulin sensitivity factor (ISF) are applied for every bolus.", comment: "Presets and illness training content, impact on bolusing, paragraph 2")
        
        ImpactView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Paloma’s bolus recommendation for 31g of carbs will increase due to her preset.", comment: "Presets and illness training content, impact on bolusing, impact title")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack(spacing: 16) {
                    Group { Text("3.9").font(.title.weight(.bold)) + Text(" U").font(.title2) }
                    
                    Text(Image(systemName: "arrow.forward"))
                        .font(.title.weight(.medium))
                    
                    Group { Text("4.3").font(.title.weight(.bold)) + Text(" U").font(.title2) }
                }
            }
        }
    }
}
