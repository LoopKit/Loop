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
        let action: () -> Void
        let label: () -> ActionLabel
        
        public init(role: ButtonRole? = nil, action: @escaping () -> Void = {}, label: @escaping () -> ActionLabel) {
            self.role = role
            self.action = action
            self.label = label
        }
    }
    
    /// Label of the Toggle
    let label: Label
    
    /// The value of the toggle to confirm before setting
    /// - A value of false means the confirmation alert will present before setting the isOn Binding to false
    /// - A value of true means the confirmation alert will present before setting the isOn Binding to true
    let confirmationValue: Bool
    
    /// The title of the alert presented when asked to confirm toggle selection
    let alertTitle: String
    
    let alertBody: String
    
    /// Action metadata of the confirmation action
    let action: Action
    
    @State private var showConfirmAlert: Bool = false
    
    @Binding  var isOn: Bool
    
    public init(
        isOn: Binding<Bool>,
        confirmationValue: Bool,
        alertTitle: String,
        alertBody: String,
        action: Action,
        showConfirmationAlert: Bool = false,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.confirmationValue = confirmationValue
        self.alertTitle = alertTitle
        self.alertBody = alertBody
        self.action = action
        self._isOn = isOn
        self.showConfirmAlert = showConfirmAlert
    }
    
    public var body: some View {
        Toggle(
            isOn: Binding(
                get: { isOn },
                set: { newValue in
                    if newValue == confirmationValue {
                        isOn = !confirmationValue
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
                    role: action.role,
                    action: {
                        isOn = confirmationValue
                        action.action()
                    },
                    label: action.label
                )
            },
            message: {Text(alertBody)})
    }
}

