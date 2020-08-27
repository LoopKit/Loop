//
//  OnOffSelectionViewModel.swift
//  WatchApp Extension
//
//  Created by Anna Quinlan on 8/20/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI

enum SelectedButton {
    case on
    case off
}

class OnOffSelectionViewModel: ObservableObject {
    var title: String
    var message: String
    var onSelection: (Bool) -> Void
    var dismiss: (() -> Void)?
    var selectedButton: SelectedButton
    var selectedButtonTint: UIColor
    
    init(
        title: String,
        message: String,
        onSelection: @escaping (Bool) -> Void,
        dismiss: (() -> Void)? = nil,
        selectedButton: SelectedButton = .off,
        selectedButtonTint: UIColor = .tintColor
    ) {
        self.title = title
        self.message = message
        self.onSelection = onSelection
        self.dismiss = dismiss
        self.selectedButton = selectedButton
        self.selectedButtonTint = selectedButtonTint
    }
}
