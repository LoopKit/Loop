//
//  PresetsAndExerciseContentView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKitUI
import SwiftUI

struct PresetsAndExerciseContentView: View {
    
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
    
    private let lowerBound = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 140)
    private let upperBound = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 160)
    
    @ViewBuilder
    var stepOneView: some View {
        HStack(alignment: .top, spacing: 16) {
            Image("workout")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 28, height: 28)
                .foregroundColor(.glucoseTintColor)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Common Scenarios", comment: "Presets and exercise training content, callout title")
                    .fontWeight(.semibold)
                
                Text("The next few screens will walk you through two common scenarios for using presets to help you better understand how this feature may work for you.", comment: "Presets and exercise training content, callout subtitle")
                    .font(.subheadline)
            }
        }
        .background(Color.accentColor.opacity(0.1).padding(.horizontal, -16).padding(.vertical, -16))
        .padding(.bottom, 24)
        .padding(.top, -8)
        
        Text("Exercise is a common use case for setting a preset. The following is an example of how a preset can support insulin management during physical activity.", comment: "Presets and exercise training content, paragraph 1")
            .bold()
        
        Text("Let’s imagine Omar Octopus wants to create a preset for a 30-minute walk to work. He wants the system to know he'll be active, so it should aim for a higher glucose correction range during that time.", comment: "Presets and exercise training content, paragraph 2")
        
        TherapySettingsExampleView(
            title: NSLocalizedString("Omar's Therapy Settings", comment: "Presets and exercise training content, therapy settings example, title"),
            basalRate: 0.5,
            carbRatio: 13,
            isf: 50
        )
        
        Text("Let’s explore each of the configurable settings that will impact Omar’s insulin delivery.", comment: "Presets and exercise training content, paragraph 3")
    }
    
    @ViewBuilder
    var stepTwoView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Insulin Needs", comment: "Presets and exercise training content, overall insulin, subtitle 1")
                .font(.title2.bold())
            
            Text("Omar asks himself, do I expect I will need more or less insulin than usual?", comment: "Presets and exercise training content, overall insulin, paragraph 1")
        }
        
        Text("In this example, Omar’s overall insulin needs remain the same for his walk, so he will not adjust the overall insulin value.", comment: "Presets and exercise training content, overall insulin, paragraph 2")
        
        Text("Pay attention to your insulin needs before and after exercising, playing sports, or doing unusually hard physical labor. ", comment: "Presets and exercise training content, overall insulin, paragraph 3")
        
        PercentPickerView(value: 100)
    
        ImpactView {
            if let string = try? AttributedString(markdown: "Omar’s **basal rate, carb ratio and insulin sensitivity factor (ISF)** remain unchanged.") {
                Text(string)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    @ViewBuilder
    var stepThreeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Correction Range", comment: "Presets and exercise training content, correction range, subtitle")
                .font(.title2.bold())
            
            let range = displayGlucosePreference.format(lowerQuantity: lowerBound, higherQuantity: upperBound)
            
            if let string = try? AttributedString(markdown: String(format: NSLocalizedString("Omar is worried he will go low while walking so he slightly increases his correction range to **%1$@**. Increasing the lower bound of the correction range tells %2$@ to begin taking action sooner.", comment: "Presets and exercise training content, correction range, paragraph 1"), range, appName)) {
                Text(string)
            }
        }
        
        Text("You may choose to set a higher temporary glucose Correction Range for physical activity where you anticipate an increased risk of low glucose.", comment: "Presets and exercise training content, correction range, paragraph 2")
        
        if let string = try? AttributedString(markdown: "For exercise, this range will typically be _**higher**_ than your usual correction range.") {
            Text(string)
        }
        
        AdjustedGlucoseRangeView(
            lowerBound: lowerBound,
            upperBound: upperBound
        )
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional: Scheduling a Preset", comment: "Presets and exercise training content, scheduling preset, subtitle")
                .font(.title2.bold())
            
            Text("Some people use this feature before exercise for a pre-programmed 1-hour, 2-hour, or indefinite length of time in an effort to decrease their risk of low glucose during exercise or other physical activity.", comment: "Presets and exercise training content, scheduling preset, paragraph 1")
        }
    }
    
    @ViewBuilder
    var stepFourView: some View {
        Text("Once saved, Omar’s completed preset will display in his Presets lists.", comment: "Presets and exercise training content, scheduling preset, paragraph 2")
        
        PresetCard(
            icon: .emoji("🚶"),
            presetName: NSLocalizedString("Walk to Work", comment: "Presets and exercise training content, scheduling preset, preset example, title"),
            duration: .duration(.seconds(1800)),
            insulinSensitivityMultiplier: 1.0,
            correctionRange: ClosedRange(
                uncheckedBounds: (
                    HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 140),
                    HKQuantity(unit: .milligramsPerDeciliter, doubleValue: 260))
            ),
            guardrail: nil,
            expectedEndTime: .indefinite
        )
    }
}
