//
//  SupportScreenView.swift
//  Loop
//
//  Created by Rick Pasetto on 8/18/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKitUI
import SwiftUI

struct SupportScreenView: View, HorizontalSizeClassOverride {
    @Environment(\.dismiss) private var dismiss
    
    var issueReport: ((_ title: String) -> Void)?
    
    var body: some View {
        List {
            Section {
                Button(action: {
                    // TODO: this "dismiss then call issueReport()" here is temporary, until we've completely gotten rid of SettingsTableViewController
                    self.dismiss()
                    self.issueReport?(NSLocalizedString("Issue Report", comment: "The title text for the issue report menu item"))
                }) {
                    Text("Issue Report", comment: "The title text for the issue report menu item")
                }
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle(Text("Support", comment: "Support screen title"))
        .environment(\.horizontalSizeClass, horizontalOverride)
    }
}

struct SupportScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SupportScreenView()
    }
}
