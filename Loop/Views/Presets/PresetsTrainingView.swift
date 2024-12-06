//
//  PresetsTrainingView.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

struct PresetsTrainingView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @StateObject var viewModel = PresetsTrainingViewModel()
    
    let onComplete: () -> Void
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            PresetsTrainingContentContainerView(
                viewModel: viewModel,
                step: .creatingYourOwnPresets,
                dismiss: { dismiss() }
            )
            .navigationDestination(for: PresetsTrainingViewModel.Step.self) { step in
                PresetsTrainingContentContainerView(
                    viewModel: viewModel,
                    step: step,
                    dismiss: { dismiss() },
                    onComplete: onComplete
                )
            }
        }
        .interactiveDismissDisabled()
    }
}
