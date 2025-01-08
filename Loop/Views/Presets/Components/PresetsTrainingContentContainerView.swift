//
//  PresetsTrainingContentContainerView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

struct PresetsTrainingContentContainerView: View {

    @ObservedObject var viewModel: PresetsTrainingViewModel
    
    @State var confirmEndTraining: Bool = false
    @State var step: PresetsTrainingViewModel.Step
    
    var dismiss: () -> Void
    let onComplete: () -> Void
    
    init(
        viewModel: PresetsTrainingViewModel,
        step: PresetsTrainingViewModel.Step,
        dismiss: @escaping () -> Void,
        onComplete: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.step = step
        self.dismiss = dismiss
        self.onComplete = onComplete
    }
    
    var body: some View {
        ViewThatFits(in: .vertical) {
            content(withSpacer: true)
            
            ScrollView {
                content()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") {
                    confirmEndTraining = true
                }
            }
        }
        .alert("End Presets Training?", isPresented: $confirmEndTraining) {
            Button("Cancel", role: .cancel) {}
            
            Button("End Training", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Ending now will require you to restart training before creating new presets.\n\nDo you want to end training?", comment: "End presets training alert message")
        }
    }
    
    private func content(withSpacer: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(step.localizedTitle)
                    .font(.largeTitle.bold())
             
                Divider()
                    .padding(.horizontal, -16)
            }
            
            switch step {
            case .creatingYourOwnPresets: CreatingYourOwnPresetsContentView()
            case .howTheyWork1: HowTheyWorkContentView(step: .one)
            case .howTheyWork2: HowTheyWorkContentView(step: .two)
            case .presetsAndExercise1: PresetsAndExerciseContentView(step: .one)
            case .presetsAndExercise2: PresetsAndExerciseContentView(step: .two)
            case .presetsAndExercise3: PresetsAndExerciseContentView(step: .three)
            case .presetsAndExercise4: PresetsAndExerciseContentView(step: .four)
            case .presetsAndIllness1: PresetsAndIllnessContentView(step: .one)
            case .presetsAndIllness2: PresetsAndIllnessContentView(step: .two)
            case .presetsAndIllness3: PresetsAndIllnessContentView(step: .three)
            case .presetsAndIllness4: PresetsAndIllnessContentView(step: .four)
            }
            
            VStack(spacing: 0) {
                if withSpacer {
                    Spacer()
                }
                
                Button {
                    if step.isFinalStep {
                        dismiss()
                        onComplete()
                    } else {
                        viewModel.nextPage()
                    }
                } label: {
                    Text(step.isFinalStep ? "Finish Training" : "Continue")
                }
                .buttonStyle(ActionButtonStyle(.primary))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom)
    }
}
