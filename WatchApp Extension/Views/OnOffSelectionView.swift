//
//  OnOffSelectionView.swift
//  WatchApp Extension
//
//  Created by Anna Quinlan on 8/20/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI

struct OnOffSelectionView: View {
    // MARK: - Initialization
    var viewModel: OnOffSelectionViewModel

    // MARK: - View Tree

    var body: some View {
        VStack {
            Spacer()
            titleStack
            Spacer()
            if viewModel.selectedButton == .on {
                buttonStackWithOnSelected
            } else if viewModel.selectedButton == .off {
                buttonStackWithOffSelected
            }
        }
    }
    
    var titleStack: some View {
        VStack(spacing: 2) {
            Text(viewModel.title)
            Text(viewModel.message)
        }
    }
    
    var buttonStackWithOnSelected: some View {
        VStack(spacing: 5) {
            onButton
            .background(Color(viewModel.selectedButtonTint).cornerRadius(20.0))
            offButton
        }
    }
    
    var buttonStackWithOffSelected: some View {
        VStack(spacing: 5) {
            onButton
            offButton
            .background(Color(viewModel.selectedButtonTint).cornerRadius(20.0))
        }
    }
    
    var onButton: some View {
        Button(action: {
            self.viewModel.onSelection(true)
            self.viewModel.dismiss?()
        }) {
            Text("On", comment: "Label for on button")
        }
        .cornerRadius(20)
    }
    
    var offButton: some View {
        Button(action: {
            self.viewModel.onSelection(false)
            self.viewModel.dismiss?()
        }) {
            Text("Off", comment: "Label for off button")
        }
        .cornerRadius(20)
    }
}

struct OnOffSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OnOffSelectionView(viewModel: OnOffSelectionViewModel(title: "Pre-Meal", message: "80-90 mg/dL", onSelection: {_ in print("hi")}, selectedButton: .on, selectedButtonTint: .carbsColor))
            .previewDevice(PreviewDevice(rawValue: "Apple Watch Series 2 - 38mm"))
            
            OnOffSelectionView(viewModel: OnOffSelectionViewModel(title: "Pre-Meal", message: "80-90 mg/dL", onSelection: {_ in print("hi")}, selectedButton: .off, selectedButtonTint: .carbsColor))
            .previewDevice(PreviewDevice(rawValue: "Apple Watch Series 2 - 42mm"))
            
            OnOffSelectionView(viewModel: OnOffSelectionViewModel(title: "Workout", message: "180-190 mg/dL", onSelection: {_ in print("hi")}, selectedButton: .on, selectedButtonTint: .glucose))
            .previewDevice(PreviewDevice(rawValue: "Apple Watch Series 4 - 44mm"))
            
            OnOffSelectionView(viewModel: OnOffSelectionViewModel(title: "Workout", message: "180-190 mg/dL", onSelection: {_ in print("hi")}, selectedButton: .off, selectedButtonTint: .glucose))
            .previewDevice(PreviewDevice(rawValue: "Apple Watch Series 4 - 40mm"))
        }
    }
}
