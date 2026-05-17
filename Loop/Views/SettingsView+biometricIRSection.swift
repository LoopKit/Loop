//
//  SettingsView+biometricIRSection.swift
//  Loop
//

import SwiftUI

extension SettingsView {
    internal var biometricIRSection: some View {
        NavigationLink(NSLocalizedString("Biometric IR", comment: "Settings row label for biometric insulin resistance")) {
            AppleHealthIRThresholdsView()
        }
    }
}
