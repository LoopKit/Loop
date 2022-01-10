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

struct SupportScreenView: View {
    @Environment(\.dismissAction) private var dismiss
    
    var didTapIssueReport: ((_ title: String) -> Void)?
    var criticalEventLogExportViewModel: CriticalEventLogExportViewModel
    let availableSupports: [SupportUI]
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
        .insetGroupedListStyle()
        .navigationBarTitle(Text("Support", comment: "Support screen title"))
    }
    
    func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }
    
    var supportMenuItems: [SupportMenuItem] {
        return availableSupports.compactMap { (support) -> SupportMenuItem? in
            if let view = support.supportMenuItem(supportInfoProvider: supportInfoProvider, urlHandler: openURL) {
                return SupportMenuItem(id: support.identifier, menuItemView: view)
            } else {
                return nil
            }
        }
    }
}

struct SupportScreenView_Previews: PreviewProvider {
    class MockSupportInfoProvider: SupportInfoProvider {
        
        var localizedAppNameAndVersion = "Loop v1.2"
        
        var pumpStatus: PumpManagerStatus? = nil
        
        var cgmStatus: CGMManagerStatus? = nil
        
        func generateIssueReport(completion: (String) -> Void) {
            completion("Mock Issue Report")
        }
    }

    static var previews: some View {
        SupportScreenView(criticalEventLogExportViewModel: CriticalEventLogExportViewModel(exporterFactory: MockCriticalEventLogExporterFactory()),
                          availableSupports: [], supportInfoProvider: MockSupportInfoProvider())
    }
}
