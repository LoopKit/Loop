//
//  EditPresetDurationView.swift
//  Loop
//
//  Created by Cameron Ingham on 12/12/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

struct EditOverrideDurationView: View {
    
    let viewModel: PresetsViewModel
    let override: TemporaryScheduleOverride
    @State var dateSelection: Date
    
    init(override: TemporaryScheduleOverride, viewModel: PresetsViewModel) {
        self.override = override
        self.viewModel = viewModel
        dateSelection = override.actualEndDate
    }
    
    var preset: SelectablePreset? {
        viewModel.allPresets.first(where: { $0.id == override.presetId })
    }
    
    var body: some View {
        ZStack {
            Color(UIColor.secondarySystemBackground)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    preset?.title(font: .largeTitle, iconSize: 36)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    DatePicker("On until", selection: $dateSelection, displayedComponents: .hourAndMinute)
                        .padding(6)
                        .padding(.leading, 10)
                        .background(Color.white.cornerRadius(10))
                    
                    Spacer()
                }
                .padding(.horizontal)
                
                Button("Save") {
                    //
                }
                .buttonStyle(ActionButtonStyle())
                .padding([.top, .horizontal])
                .background(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: -4)
                .disabled(dateSelection == override.actualEndDate)
            }
        }
    }
}
