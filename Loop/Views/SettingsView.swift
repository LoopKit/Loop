//
//  SettingsView.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/24/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import SwiftUI

public struct SettingsView: View, HorizontalSizeClassOverride {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appName) private var appName

    @ObservedObject var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            List {
                loopSection
                if viewModel.showWarning {
                    alertPermissionsSection
                }
                therapySettingsSection
                deviceSettingsSection
                supportSection
            }
            .listStyle(GroupedListStyle())
            .navigationBarTitle(Text(NSLocalizedString("Settings", comment: "Settings screen title")))
            .navigationBarItems(trailing: dismissButton)
            .environment(\.horizontalSizeClass, horizontalOverride)
        }
    }
    
}

extension SettingsView {
        
    private var dismissButton: some View {
        Button(action: { self.dismiss() }) {
            Text("Done").bold()
        }
    }
    
    private var loopSection: some View {
        Section(header: SectionHeader(label: viewModel.appNameAndVersion)) {
            Toggle(isOn: $viewModel.dosingEnabled) {
                Text(NSLocalizedString("Closed Loop", comment: "The title text for the looping enabled switch cell"))
            }
        }
    }
    
    private var alertPermissionsSection: some View {
        Section {
            NavigationLink(destination:
                NotificationsCriticalAlertPermissionsView(mode: .flow, viewModel: NotificationsCriticalAlertPermissionsViewModel()))
            {
                HStack {
                    Text(NSLocalizedString("Alert Permissions", comment: "Alert Permissions button text"))
                    if viewModel.showWarning {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.critical)
                    }
                }
            }
        }
    }
        
    private var therapySettingsSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Configuration", comment: "The title of the Configuration section in settings"))) {
            return NavigationLink(destination: TherapySettingsView(viewModel: TherapySettingsViewModel(mode: .settings,
                                                                                                       therapySettings: viewModel.therapySettings,
                                                                                                       supportedInsulinModelSettings: viewModel.supportedInsulinModelSettings,
                                                                                                       pumpSupportedIncrements: viewModel.pumpSupportedIncrements,
                                                                                                       syncPumpSchedule: viewModel.syncPumpSchedule,
                                                                                                       didSave: viewModel.didSave))) {
                LargeButton(action: { },
                            includeArrow: false,
                            imageView: AnyView(Image("Therapy Icon")),
                            label: NSLocalizedString("Therapy Settings", comment: "Title text for button to Therapy Settings"),
                            descriptiveText: NSLocalizedString("Diabetes Treatment", comment: "Descriptive text for Therapy Settings"))
            }
        }
    }
    
    private var deviceSettingsSection: some View {
        Section {
            pumpSection
            cgmSection
        }
    }
    
    private var pumpSection: some View {
        if viewModel.pumpManagerSettingsViewModel.isSetUp {
            // TODO: this "dismiss then call onTapped()" here is temporary, until we've completely gotten rid of SettingsTableViewController
            return LargeButton(action: { self.dismiss(); self.viewModel.pumpManagerSettingsViewModel.onTapped() },
                               imageView: deviceImage(uiImage: viewModel.pumpManagerSettingsViewModel.image),
                               label: viewModel.pumpManagerSettingsViewModel.name,
                               descriptiveText: NSLocalizedString("Insulin Pump", comment: "Descriptive text for Insulin Pump"))
        } else {
            // TODO: this "dismiss then call onTapped()" here is temporary, until we've completely gotten rid of SettingsTableViewController
            return LargeButton(action: { self.dismiss(); self.viewModel.pumpManagerSettingsViewModel.onTapped() },
                               imageView: AnyView(plusImage),
                               label: NSLocalizedString("Add Pump", comment: "Title text for button to add pump device"),
                               descriptiveText: NSLocalizedString("Tap here to set up a pump", comment: "Descriptive text for button to add pump device"))
        }
    }
    
    private var cgmSection: some View {
        if viewModel.cgmManagerSettingsViewModel.isSetUp {
            // TODO: this "dismiss then call onTapped()" here is temporary, until we've completely gotten rid of SettingsTableViewController
            return LargeButton(action: { self.dismiss(); self.viewModel.cgmManagerSettingsViewModel.onTapped() },
                               imageView: deviceImage(uiImage: viewModel.cgmManagerSettingsViewModel.image),
                               label: viewModel.cgmManagerSettingsViewModel.name,
                               descriptiveText: NSLocalizedString("Continuous Glucose Monitor", comment: "Descriptive text for Continuous Glucose Monitor"))
        } else {
            // TODO: this "dismiss then call onTapped()" here is temporary, until we've completely gotten rid of SettingsTableViewController
            return LargeButton(action: { self.dismiss(); self.viewModel.cgmManagerSettingsViewModel.onTapped() },
                               imageView: AnyView(plusImage),
                               label: NSLocalizedString("Add CGM", comment: "Title text for button to add CGM device"),
                               descriptiveText: NSLocalizedString("Tap here to set up a CGM", comment: "Descriptive text for button to add CGM device"))
        }
    }
    
    private var supportSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Support", comment: "The title of the support section in settings"))) {
            NavigationLink(destination: Text("Support")) {
                Text(NSLocalizedString("Support", comment: "The title of the support section in settings"))
            }
        }
    }

    private var plusImage: some View {
        Image(systemName: "plus.circle")
            .resizable()
            .scaledToFit()
            .accentColor(.blue)
    }
    
    private func deviceImage(uiImage: UIImage?) -> AnyView {
        if let uiImage = uiImage {
            return AnyView(Image(uiImage: uiImage)
                .renderingMode(.original)
                .resizable()
                .scaledToFit())
        } else {
            return AnyView(Spacer())
        }
    }
}

fileprivate struct LargeButton: View {
    
    let action: () -> Void
    var includeArrow: Bool = true
    let imageView: AnyView
    let label: String
    let descriptiveText: String

    // TODO: The design doesn't show this, but do we need to consider different values here for different size classes?
    static let spacing: CGFloat = 15
    static let imageWidth: CGFloat = 48
    static let imageHeight: CGFloat = 48
    static let topBottomPadding: CGFloat = 20
    
    public var body: some View {
        Button(action: action) {
            HStack {
                HStack(spacing: Self.spacing) {
                    imageView.frame(width: Self.imageWidth, height: Self.imageHeight)
                    VStack(alignment: .leading) {
                        Text(label)
                            .foregroundColor(.primary)
                        DescriptiveText(label: descriptiveText)
                    }
                }
                if includeArrow {
                    Spacer()
                    // TODO: Ick. I can't use a NavigationLink because we're not Navigating, but this seems worse somehow.
                    Image(systemName: "chevron.right").foregroundColor(.gray).font(.footnote)
                }
            }
            .padding(EdgeInsets(top: Self.topBottomPadding, leading: 0, bottom: Self.topBottomPadding, trailing: 0))
        }
    }
}

public struct SettingsView_Previews: PreviewProvider {
    public static var previews: some View {
        let viewModel = SettingsViewModel(appNameAndVersion: "Tidepool Loop v1.2.3.456",
                                          notificationsCriticalAlertPermissionsViewModel: NotificationsCriticalAlertPermissionsViewModel(),
                                          pumpManagerSettingsViewModel: DeviceViewModel(),
                                          cgmManagerSettingsViewModel: DeviceViewModel(),
                                          therapySettings: TherapySettings(),
                                          supportedInsulinModelSettings: SupportedInsulinModelSettings(fiaspModelEnabled: true, walshModelEnabled: true),
                                          pumpSupportedIncrements: nil,
                                          syncPumpSchedule: nil,
                                          sensitivityOverridesEnabled: false,
                                          initialDosingEnabled: true)
        return Group {
            SettingsView(viewModel: viewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE 2"))
                .previewDisplayName("SE light")
            
            SettingsView(viewModel: viewModel)
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone XS Max"))
                .previewDisplayName("XS Max dark")
        }
    }
}
