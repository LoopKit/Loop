//
//  SettingsView+algorithmExperimentsSection.swift
//  Loop
//
//  Created by Jonas Björkert on 2023-06-03.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKitUI

extension SettingsView {
    internal var algorithmExperimentsSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Algorithm Experiments ⚠️", comment: "The title of the Algorithm Experiments section in settings"))) {

            NavigationLink(destination: GlucoseBasedApplicationFactorSelectionView(isGlucoseBasedApplicationFactorEnabled: $isGlucoseBasedApplicationFactorEnabled)) {
                HStack {
                    Text("Glucose Based Partial Application")
                    Spacer()
                    Text(isGlucoseBasedApplicationFactorEnabled ? "On" : "Off")
                }
            }
        }
    }
}
