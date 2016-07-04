//
//  ServiceCredential.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


// Represents a credential for a service, including its text input traits
struct ServiceCredential {
    // The localized title of the credential (e.g. "Username")
    let title: String

    // The localized placeholder text to assist text input
    let placeholder: String?

    // Whether the credential is considered secret. Correponds to the `secureTextEntry` trait.
    let isSecret: Bool

    // The type of keyboard to use to enter the credential
    let keyboardType: UIKeyboardType

    // The credential value
    var value: String?
}
