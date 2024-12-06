//
//  PresetsTrainingCard.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

struct PresetsTrainingCard: View {
    
    @Environment(\.appName) private var appName
    
    @Binding var showTraining: Bool
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                Text(String(format: NSLocalizedString("Take more control of your insulin management with presets. Presets inform %1$@ that you anticipate a temporary change in how your diabetes behaves.", comment: "Presets training card, paragraph 1"), appName))
                    .multilineTextAlignment(.center)
                
                Text("Complete the preset training to begin creating your own custom presets.", comment: "Presets training card, paragraph 2")
                    .multilineTextAlignment(.center)
            }
            
            Button("Start Preset Training") {
                showTraining = true
            }
            .buttonStyle(ActionButtonStyle(.primary))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill( Color(UIColor.tertiarySystemBackground)))
    }
}
