//
//  ConfirmationToggle.swift
//  LoopUI
//
//  Created by Arwain Karlin on 5/8/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

public struct ConfirmationToggle<Label: View, ActionLabel: View>: View {
    
    public struct Action {
        let role: ButtonRole?
        let label: () -> ActionLabel
        
        public init(role: ButtonRole? = nil, label: @escaping () -> ActionLabel) {
            self.role = role
            self.label = label
        }
    }
    
    /// Label of the Toggle
    private let label: Label
    
    /// The value of the toggle to confirm before setting
    /// - A value of false means the confirmation alert will present before setting the isOn Binding to false
    /// - A value of true means the confirmation alert will present before setting the isOn Binding to true
    private let confirmOn: Bool
    
    /// The title of the alert presented when asked to confirm toggle selection
    private let alertTitle: String
    
    /// The body of the alert presented when asked to confirm toggle selection
    private let alertBody: String
    
    /// Action metadata of the confirmation action
    private let confirmAction: Action
    
    /// Determines display of alert confirming toggled state
    @State private var showConfirmAlert: Bool = false
    
    /// State of the toggle
    @Binding private var isOn: Bool
    
    /// Creates a ConfirmationToggle
    /// - Parameters:
    ///   - isOn: State of the toggle
    ///   - confirmOn: The value of the toggle to confirm before setting
    ///   - alertTitle: The title of the alert presented when asked to confirm toggle selection
    ///   - alertBody: The body of the alert presented when asked to confirm toggle selection
    ///   - confirmAction: Action metadata of the confirmation action
    ///   - label: Label of the Toggle
    public init(
        isOn: Binding<Bool>,
        confirmOn: Bool,
        alertTitle: String,
        alertBody: String,
        confirmAction: Action,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.confirmOn = confirmOn
        self.alertTitle = alertTitle
        self.alertBody = alertBody
        self.confirmAction = confirmAction
        self._isOn = isOn
        self.showConfirmAlert = showConfirmAlert
    }
    
    public var body: some View {
        Toggle(
            isOn: Binding(
                get: { isOn },
                set: { newValue in
                    if newValue == confirmOn {
                        isOn = !confirmOn
                        showConfirmAlert = true
                    } else {
                        isOn = newValue
                    }
                }
            )
        ) {
            label
        }
        .alert(
            alertTitle,
            isPresented: $showConfirmAlert,
            actions: {
                Button(
                    role: .cancel,
                    action: {},
                    label: { Text("Cancel") }
                )
                
                Button(
                    role: confirmAction.role,
                    action: {
                        isOn = confirmOn
                    },
                    label: confirmAction.label
                )
            },
            message: { Text(alertBody) }
        )
    }
}

