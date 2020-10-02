//
//  SupportScreenView.swift
//  Loop
//
//  Created by Rick Pasetto on 8/18/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

struct SupportScreenView: View, HorizontalSizeClassOverride {
    @Environment(\.dismiss) private var dismiss
    
    var didTapIssueReport: ((_ title: String) -> Void)?
    var criticalEventLogExportViewModel: CriticalEventLogExportViewModel
    let adverseEventReportViewModel: AdverseEventReportViewModel
    
    @State private var adverseEventReportURLInvalid = false

    var body: some View {
        List {
            Section {
                Button(action: {
                    self.didTapIssueReport?(NSLocalizedString("Issue Report", comment: "The title text for the issue report menu item"))
                }) {
                    Text("Issue Report", comment: "The title text for the issue report menu item")
                }
                
                adverseEventReport
                
                NavigationLink(destination: CriticalEventLogExportView(viewModel: self.criticalEventLogExportViewModel)) {
                    Text(NSLocalizedString("Export Critical Event Logs", comment: "The title of the export critical event logs in support"))
                }
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle(Text("Support", comment: "Support screen title"))
        .environment(\.horizontalSizeClass, horizontalOverride)
    }
    
    private var adverseEventReport: some View {
        Button(action: {
            guard let url = self.adverseEventReportViewModel.reportURL else {
                self.adverseEventReportURLInvalid = true
                return
            }
            
            UIApplication.shared.open(url)
        }) {
            Text("Report an Adverse Event", comment: "The title text for the reporting of an adverse event menu item")
        }
        .alert(isPresented: $adverseEventReportURLInvalid) {
            invalidAdverseEventReportURLAlert
        }
    }
    
    private var invalidAdverseEventReportURLAlert: SwiftUI.Alert {
        Alert(title: Text("Invalid Adverse Event Report URL", comment: "Alert title when the adverse event report URL cannot be constructed properly."),
              message: Text("The adverse event report URL could not be constructed properly.", comment: "Alert message when the adverse event report URL cannot be constructed properly."),
              dismissButton: .default(Text("Dismiss", comment: "Dismiss button for the invalid adverse event report URL alert.")))
    }
}

struct SupportScreenView_Previews: PreviewProvider {
    static var previews: some View {
        SupportScreenView(criticalEventLogExportViewModel: CriticalEventLogExportViewModel(exporterFactory: MockCriticalEventLogExporterFactory()),
                          adverseEventReportViewModel: AdverseEventReportViewModel())
    }
}
