//
//  SettingsView+underDevelopmentSection.swift
//  Loop
//
//  Created by Moti Nisenson-Ken on 14/01/2025.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI
import LoopKit
import LoopKitUI

extension SettingsView {
    internal var underDevelopmentSection: some View {
        NavigationLink(NSLocalizedString("🚧 Under Development 🚧", comment: "The title of the Under Development section in settings")) {
            UnderDevelopmentSettingsView()
        }
    }
}

public struct UnderDevelopmentSettingsView: View {
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 12) {
                Text(NSLocalizedString("🚧 Under Development 🚧", comment: "Navigation title for under development screen"))
                    .font(.headline)
                VStack {
                    Text("⚠️").font(.largeTitle)
                    Text("Caution")
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("These features are under development. They may not have been tested thorougly.", comment: "Under Development description."))
                    Text(NSLocalizedString("In future versions of Loop these features may change, end up as standard parts of Loop, or be removed from Loop entirely. Please follow along in the Loop Zulip chat to stay informed of possible changes to these features.", comment: "Under development description second paragraph."))
                }
                .foregroundColor(.secondary)

                Divider()
                NavigationLink(destination: CarbBolusSelectionView()) {
                    ExperimentRow(name: NSLocalizedString("Carb Bolus Recommendation", comment: "Title of carb bolus recommendation feature"), enabled: nil)
                }
                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
