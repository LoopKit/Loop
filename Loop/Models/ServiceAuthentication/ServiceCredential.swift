//
//  ServiceCredential.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


/// Represents a credential for a service, including its text input traits
struct ServiceCredential {
    /// The localized title of the credential (e.g. "Username")
    let title: String

    /// The localized placeholder text to assist text input
    let placeholder: String?

    /// Whether the credential is considered secret. Correponds to the `secureTextEntry` trait.
    let isSecret: Bool

    /// The type of keyboard to use to enter the credential
    let keyboardType: UIKeyboardType

    /// The credential value
    var value: String?

    /// A set of valid values for presenting a selection. The first item is the default.
    var options: [(title: String, value: String)]?

    init(title: String, placeholder: String? = nil, isSecret: Bool, keyboardType: UIKeyboardType = .asciiCapable, value: String?, options: [(title: String, value: String)]? = nil) {
        self.title = title
        self.placeholder = placeholder
        self.isSecret = isSecret
        self.keyboardType = keyboardType
        self.value = value ?? options?.first?.value
        self.options = options
    }

    mutating func reset() {
        self.value = options?.first?.value
    }
}
