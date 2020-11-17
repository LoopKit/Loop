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
import HealthKit

struct SupportMenuItem: Identifiable {
    var id: String
    var menuItemView: AnyView
}

struct SupportScreenView: View, HorizontalSizeClassOverride {
    @Environment(\.dismiss) private var dismiss
    
    var didTapIssueReport: ((_ title: String) -> Void)?
    var criticalEventLogExportViewModel: CriticalEventLogExportViewModel
    let activeServices: [Service]
    let supportInfoProvider: SupportInfoProvider
    
    @State private var adverseEventReportURLInvalid = false

    var body: some View {
        List {
            Section {
                Button(action: {
                    self.didTapIssueReport?(NSLocalizedString("Issue Report", comment: "The title text for the issue report menu item"))
                }) {
                    Text("Issue Report", comment: "The title text for the issue report menu item")
                }
                
                ForEach(supportMenuItems) {
                    $0.menuItemView
                }
        
                NavigationLink(destination: CriticalEventLogExportView(viewModel: self.criticalEventLogExportViewModel)) {
                    Text(NSLocalizedString("Export Critical Event Logs", comment: "The title of the export critical event logs in support"))
                }
            }
        }
        .listStyle(GroupedListStyle())
        .navigationBarTitle(Text("Support", comment: "Support screen title"))
        .environment(\.horizontalSizeClass, horizontalOverride)
    }
    
    func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }
    
    var supportMenuItems: [SupportMenuItem] {
        return activeServices.compactMap { (service) -> SupportMenuItem? in
            if let view = (service as? ServiceUI)?.supportMenuItem(supportInfoProvider: supportInfoProvider, urlHandler: openURL) {
                return SupportMenuItem(id: service.serviceIdentifier, menuItemView: view)
            } else {
                return nil
            }
        }
    }
        
    private var invalidAdverseEventReportURLAlert: SwiftUI.Alert {
        Alert(title: Text("Invalid Adverse Event Report URL", comment: "Alert title when the adverse event report URL cannot be constructed properly."),
              message: Text("The adverse event report URL could not be constructed properly.", comment: "Alert message when the adverse event report URL cannot be constructed properly."),
              dismissButton: .default(Text("Dismiss", comment: "Dismiss button for the invalid adverse event report URL alert.")))
    }
}

struct SupportScreenView_Previews: PreviewProvider {
    class MockSupportInfoProvider: SupportInfoProvider {
        
        var localizedAppNameAndVersion = "Loop v1.2"
        
        var pumpStatus: PumpManagerStatus? = nil
        
        var cgmDevice: HKDevice? = nil
        
        func generateIssueReport(completion: (String) -> Void) {
            completion("Mock Issue Report")
        }
    }

    static var previews: some View {
        SupportScreenView(criticalEventLogExportViewModel: CriticalEventLogExportViewModel(exporterFactory: MockCriticalEventLogExporterFactory()),
                          activeServices: [], supportInfoProvider: MockSupportInfoProvider())
    }
}
