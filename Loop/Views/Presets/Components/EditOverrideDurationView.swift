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
    
    @Environment(\.dismiss) private var dismiss
    
    let viewModel: PresetsViewModel
    let override: TemporaryScheduleOverride
    
    @State var dateSelection: Date

    private let currentDate: Date
    
    init(override: TemporaryScheduleOverride, viewModel: PresetsViewModel) {
        self.override = override
        self.viewModel = viewModel
        self.currentDate = Date()
        
        if case let .duration(timeInterval) = viewModel.activePreset?.duration {
            dateSelection = override.startDate.addingTimeInterval(timeInterval)
        } else {
            dateSelection = currentDate
        }
    }
    
    var preset: SelectablePreset? {
        viewModel.allPresets.first(where: { $0.id == override.presetId })
    }
    
    var buttonDisabled: Bool {
        if case .duration = viewModel.activePreset?.duration {
            return dateSelection == override.actualEndDate
        } else if case .indefinite = viewModel.activePreset?.duration {
            return false
        } else {
            return dateSelection == currentDate
        }
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
                    viewModel.updateActivePresetDuration(newEndDate: dateSelection)
                    dismiss()
                }
                .buttonStyle(ActionButtonStyle())
                .padding([.top, .horizontal])
                .background(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: -4)
                .disabled(buttonDisabled)
            }
        }
    }
}
