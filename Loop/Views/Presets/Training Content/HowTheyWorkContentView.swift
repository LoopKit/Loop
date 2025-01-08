//
//  HowTheyWorkContentView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

struct HowTheyWorkContentView: View {
    
    @Environment(\.appName) private var appName
    
    enum StepNumber {
        case one
        case two
    }
    
    let step: StepNumber
    
    var body: some View {
        switch step {
        case .one:
            stepOneView
        case .two:
            stepTwoView
        }
    }
    
    @ViewBuilder
    var stepOneView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The most important settings when creating a preset will be those that impact your insulin delivery and safety:", comment: "How presets work training content, paragraph 1")
            
            BulletedListView {
                Text("Overall insulin", comment: "How presets work training content, paragraph 1, bullet 1")
                
                Text("Correction range", comment: "How presets work training content, paragraph 1, bullet 2")
            }
        }
        
        Text("Let's do a brief review of each setting.", comment: "How presets work training content, paragraph 2")
        
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjusting Overall Insulin", comment: "How presets work training content, adjusting overall insulin, subtitle 1")
                .font(.title2.bold())
            
            if let image = Image("PresetsTraining3") {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityHidden(true)
            }
            
            Text("Presets allow you to specify an adjusted overall insulin value for the duration of the preset.", comment: "How presets work training content, adjusting overall insulin, paragraph 1")
        }
        
        VStack(alignment: .leading, spacing: 8) {
            Group {
                Text("Overall insulin is a ", comment: "How presets work training content, adjusting overall insulin, subtitle 1, paragraph 2, part 1") + Text("metabolic", comment: "How presets work training content, adjusting overall insulin, paragraph 2, part 2").bold() + Text(" setting and should be used when your body needs more or less insulin than normal. Adjusting the overall insulin percentage will impact the following settings:", comment: "How presets work training content, adjusting overall insulin, paragraph 2, part 3")
            }
            
            BulletedListView {
                Text("Basal Rate", comment: "How presets work training content, adjusting overall insulin, paragraph 2, bullet 1")
                
                Text("Carb Ratio", comment: "How presets work training content, adjusting overall insulin, paragraph 2, bullet 2")
                
                Text("Insulin Sensitivity Factor (ISF)", comment: "How presets work training content, adjusting overall insulin, paragraph 2, bullet 3")
            }
        }
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Before adjusting your overall insulin, ask yourself, does my body need more or less than normal?", comment: "How presets work training content, adjusting overall insulin, paragraph 3").bold()
            
            if
                let lower = try? AttributedString(markdown: "Setting a percentage _**lower**_ than 100% will let the system know that you are more insulin sensitive and need less insulin."),
                let higher = try? AttributedString(markdown: "Setting a percentage _**higher**_ than 100% will let the system know that you are more insulin resistant and need more insulin.")
            {
                BulletedListView {
                    Text(lower)
                    
                    Text(higher)
                }
            }
        }
    }
    
    @ViewBuilder
    var stepTwoView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjusting the Correction Range", comment: "How presets work training content, adjusting correction range, subtitle 1")
                .font(.title2.bold())
            
            if let image = Image("PresetsTraining4") {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityHidden(true)
            }
        }
        
        Text("Presets allow you to specify an adjusted correction range for the duration of the preset to help you meet your glucose goals.", comment: "How presets work training content, adjusting correction range, paragraph 1")
        
        Text(String(format: NSLocalizedString("It allows you to choose the specific glucose value (or range of values) that you want %1$@ to aim for in adjusting your basal insulin.", comment: "How presets work training content, adjusting correction range, paragraph 2"), appName))
        
        if let string = try? AttributedString(markdown: "The correction range is a **safety** setting. Changing the correction range from your scheduled correction range may be particularly useful in reducing the risk of lows / hypoglycemia if you expect your glucose to vary more than normal.") {
            Text(string)
                .fixedSize(horizontal: false, vertical: true)
        }
        
        Text("You do not have to set a new correction range for each preset.", comment: "How presets work training content, adjusting correction range, paragraph 4")
        
        Text("Before adjusting your correction range, ask yourself, am I more likely to go high or low during this event?", comment: "How presets work training content, adjusting correction range, paragraph 5")
            .bold()
    }
}
