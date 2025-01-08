//
//  CreatingYourOwnPresetsContentView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopUI
import LoopKitUI
import SwiftUI

struct CreatingYourOwnPresetsContentView: View {
    
    @Environment(\.appName) private var appName
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: NSLocalizedString("%1$@ comes with two provider recommended presets with your prescription:", comment: "Creating your own presets training content, paragraph 1"), appName))
            
            BulletedListView {
                Text(Image("Pre-Meal-symbol")).foregroundColor(.carbTintColor) + Text(" Pre-Meal")
                Text(Image("workout-symbol")).foregroundColor(.glucoseTintColor) + Text(" Workout")
            }
        }
        
        Text(String(format: NSLocalizedString("After reviewing this required training, you’ll be able to create your own custom presets. This is an optional feature that can enhance and personalize how the %1$@ system works for you.", comment: "Creating your own presets training content, paragraph 2"), appName))
        
        Text("Using presets, you can let the system know about events that may impact your diabetes management such as exercising, sickness or hormonal changes.", comment: "Creating your own presets training content, paragraph 3")
        
        Text("We encourage you to work with your healthcare provider to find the right preset settings for you.", comment: "Creating your own presets training content, paragraph 4")
        
        VStack(alignment: .leading, spacing: 8) {
            Text("Managing Presets", comment: "Creating your own presets training content, managing presets, subtitle 1")
                .font(.title2.bold())
            
            Text("You can manage all presets by tapping the Presets button on the toolbar.", comment: "Creating your own presets training content, managing presets, paragraph 1")
            
            if let image = Image("PresetsTraining1") {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityHidden(true)
            }
        }
        
        VStack(alignment: .leading, spacing: 8) {
            Text("When a preset is ON, you’ll notice the following indicators on the home screen:", comment: "Creating your own presets training content, managing presets, paragraph 2")
            
            BulletedListView {
                Text("the Presets button will display with inverted colors on the toolbar", comment: "Creating your own presets training content, managing presets, paragraph 2, bullet 1")
                Text("a banner will display at the top of the home screen", comment: "Creating your own presets training content, managing presets, paragraph 2, bullet 2")
                Text("(if applicable) the glucose chart will show your adjusted correction range", comment: "Creating your own presets training content, managing presets, paragraph 2, bullet 3")
            }
            
            if let image = Image("PresetsTraining2") {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityHidden(true)
            }
        }
    }
}
