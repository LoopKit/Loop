//
//  SettingsView.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/24/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import MockKit
import SwiftUI
import HealthKit

public struct SettingsView: View {
    @EnvironmentObject private var displayGlucoseUnitObservable: DisplayGlucoseUnitObservable
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.appName) private var appName
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.carbTintColor) private var carbTintColor
    @Environment(\.glucoseTintColor) private var glucoseTintColor
    @Environment(\.insulinTintColor) private var insulinTintColor

    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var versionUpdateViewModel: VersionUpdateViewModel

    @State private var pumpChooserIsPresented: Bool = false
    @State private var cgmChooserIsPresented: Bool = false
    @State private var serviceChooserIsPresented: Bool = false
    @State private var therapySettingsIsPresented: Bool = false
    @State private var deletePumpDataAlertIsPresented = false
    @State private var deleteCGMDataAlertIsPresented = false

    var localizedAppNameAndVersion: String

    public init(viewModel: SettingsViewModel, localizedAppNameAndVersion: String) {
        self.viewModel = viewModel
        self.versionUpdateViewModel = viewModel.versionUpdateViewModel
        self.localizedAppNameAndVersion = localizedAppNameAndVersion
    }
    
    public var body: some View {
        NavigationView {
            List {
                Group {
                    loopSection
                    if versionUpdateViewModel.softwareUpdateAvailable {
                        softwareUpdateSection
                    }
                    if FeatureFlags.automaticBolusEnabled {
                        dosingStrategySection
                    }
                    alertManagementSection
                    if viewModel.pumpManagerSettingsViewModel.isSetUp() {
                        configurationSection
                    }
                    deviceSettingsSection
                    if viewModel.pumpManagerSettingsViewModel.isTestingDevice || viewModel.cgmManagerSettingsViewModel.isTestingDevice {
                        deleteDataSection
                    }
                }
                Group {
                    if viewModel.servicesViewModel.showServices {
                        servicesSection
                    }

                    ForEach(customSections) { customSectionName in
                        menuItemsForSection(name: customSectionName)
                    }

                    supportSection

                    if let profileExpiration = Bundle.main.profileExpiration, FeatureFlags.profileExpirationSettingsViewEnabled {
                        profileExpirationSection(profileExpiration: profileExpiration)
                    }
                }
            }
            .insetGroupedListStyle()
            .navigationBarTitle(Text(NSLocalizedString("Settings", comment: "Settings screen title")))
            .navigationBarItems(trailing: dismissButton)
        }
        .navigationViewStyle(.stack)
    }

    private func menuItemsForSection(name: String) -> some View {
        Section(header: SectionHeader(label: name)) {
            ForEach(pluginMenuItems.filter {$0.section.customLocalizedTitle == name}) { item in
                item.view
            }
        }
    }

    private var customSections: [String] {
        pluginMenuItems.compactMap { item in
            if case .custom(let name) = item.section {
                return name
            } else {
                return nil
            }
        }
    }
    
    private var closedLoopToggleState: Binding<Bool> {
        Binding(
            get: { self.viewModel.isClosedLoopAllowed && self.viewModel.closedLoopPreference },
            set: { self.viewModel.closedLoopPreference = $0 }
        )
    }
}

extension String: Identifiable {
    public typealias ID = Int
    public var id: Int {
        return hash
    }
}

struct PluginMenuItem: Identifiable {
    var id: String {
        return pluginIdentifier + String(describing: offset)
    }

    let section: SettingsMenuSection
    let view: AnyView
    let pluginIdentifier: String
    let offset: Int
}

extension SettingsView {
        
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Done").bold()
        }
    }
    
    private var loopSection: some View {
        Section(header: SectionHeader(label: localizedAppNameAndVersion)) {
            Toggle(isOn: closedLoopToggleState) {
                VStack(alignment: .leading) {
                    Text("Closed Loop", comment: "The title text for the looping enabled switch cell")
                        .padding(.vertical, 3)
                    if !viewModel.isOnboardingComplete {
                        DescriptiveText(label: NSLocalizedString("Closed Loop requires Setup to be Complete", comment: "The description text for the looping enabled switch cell when onboarding is not complete"))
                    } else if let closedLoopDescriptiveText = viewModel.closedLoopDescriptiveText {
                        DescriptiveText(label: closedLoopDescriptiveText)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!viewModel.isOnboardingComplete || !viewModel.isClosedLoopAllowed)
        }
    }
    
    private var softwareUpdateSection: some View {
        Section(footer: Text(viewModel.versionUpdateViewModel.footer(appName: appName))) {
            NavigationLink(destination: viewModel.versionUpdateViewModel.softwareUpdateView) {
                Text(NSLocalizedString("Software Update", comment: "Software update button link text"))
                Spacer()
                viewModel.versionUpdateViewModel.icon
            }
        }
    }

    private var dosingStrategySection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Dosing Strategy", comment: "The title of the Dosing Strategy section in settings"))) {
            
            NavigationLink(destination: DosingStrategySelectionView(automaticDosingStrategy: $viewModel.automaticDosingStrategy))
            {
                HStack {
                    Text(viewModel.automaticDosingStrategy.title)
                }
            }
        }
    }

    private var alertManagementSection: some View {
        Section {
            NavigationLink(destination: AlertManagementView(checker: viewModel.alertPermissionsChecker, alertMuter: viewModel.alertMuter))
            {
                HStack {
                    Text(NSLocalizedString("Alert Management", comment: "Alert Permissions button text"))
                    if viewModel.alertPermissionsChecker.showWarning ||
                        viewModel.alertPermissionsChecker.notificationCenterSettings.scheduledDeliveryEnabled {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.critical)
                    } else if viewModel.alertMuter.configuration.shouldMute {
                        Spacer()
                        Image(systemName: "speaker.slash.fill")
                            .foregroundColor(.white)
                            .padding(5)
                            .background(guidanceColors.warning)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
            }
        }
    }
        
    private var configurationSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Configuration", comment: "The title of the Configuration section in settings"))) {
            LargeButton(action: { self.therapySettingsIsPresented = true },
                            includeArrow: true,
                            imageView: AnyView(Image("Therapy Icon")),
                            label: NSLocalizedString("Therapy Settings", comment: "Title text for button to Therapy Settings"),
                            descriptiveText: NSLocalizedString("Diabetes Treatment", comment: "Descriptive text for Therapy Settings"))
                .sheet(isPresented: $therapySettingsIsPresented) {
                    TherapySettingsView(mode: .settings,
                                        viewModel: TherapySettingsViewModel(therapySettings: self.viewModel.therapySettings(),
                                                                            sensitivityOverridesEnabled: FeatureFlags.sensitivityOverridesEnabled,
                                                                            adultChildInsulinModelSelectionEnabled: FeatureFlags.adultChildInsulinModelSelectionEnabled,
                                                                            delegate: self.viewModel.therapySettingsViewModelDelegate))
                        .environmentObject(displayGlucoseUnitObservable)
                        .environment(\.dismissAction, self.dismiss)
                        .environment(\.appName, self.appName)
                        .environment(\.chartColorPalette, .primary)
                        .environment(\.carbTintColor, self.carbTintColor)
                        .environment(\.glucoseTintColor, self.glucoseTintColor)
                        .environment(\.guidanceColors, self.guidanceColors)
                        .environment(\.insulinTintColor, self.insulinTintColor)
            }
            
            ForEach(pluginMenuItems.filter {$0.section == .configuration}) { item in
                item.view
            }
        }
    }

    private var pluginMenuItems: [PluginMenuItem] {
        self.viewModel.availableSupports.flatMap { plugin in
            plugin.configurationMenuItems().enumerated().map { index, item in
                PluginMenuItem(section: item.section, view: item.view, pluginIdentifier: plugin.identifier, offset: index)
            }
        }
    }

    private var deviceSettingsSection: some View {
        Section {
            pumpSection
            cgmSection
        }
    }
    
    @ViewBuilder
    private var pumpSection: some View {
        if viewModel.pumpManagerSettingsViewModel.isSetUp() {
            LargeButton(action: self.viewModel.pumpManagerSettingsViewModel.didTap,
                        includeArrow: true,
                        imageView: deviceImage(uiImage: viewModel.pumpManagerSettingsViewModel.image()),
                        label: viewModel.pumpManagerSettingsViewModel.name(),
                        descriptiveText: NSLocalizedString("Insulin Pump", comment: "Descriptive text for Insulin Pump"))
        } else if viewModel.isOnboardingComplete {
            LargeButton(action: { self.pumpChooserIsPresented = true },
                        includeArrow: false,
                        imageView: AnyView(plusImage),
                        label: NSLocalizedString("Add Pump", comment: "Title text for button to add pump device"),
                        descriptiveText: NSLocalizedString("Tap here to set up a pump", comment: "Descriptive text for button to add pump device"))
                .actionSheet(isPresented: $pumpChooserIsPresented) {
                    ActionSheet(title: Text("Add Pump", comment: "The title of the pump chooser in settings"), buttons: pumpChoices)
            }
        } else {
            EmptyView()
        }
    }
    
    private var pumpChoices: [ActionSheet.Button] {
        var result = viewModel.pumpManagerSettingsViewModel.availableDevices.map { availableDevice in
            ActionSheet.Button.default(Text(availableDevice.localizedTitle)) {
                self.viewModel.pumpManagerSettingsViewModel.didTapAdd(availableDevice)
            }
        }
        result.append(.cancel())
        return result
    }
    
    @ViewBuilder
    private var cgmSection: some View {
        if viewModel.cgmManagerSettingsViewModel.isSetUp() {
            LargeButton(action: self.viewModel.cgmManagerSettingsViewModel.didTap,
                        includeArrow: true,
                        imageView: deviceImage(uiImage: viewModel.cgmManagerSettingsViewModel.image()),
                        label: viewModel.cgmManagerSettingsViewModel.name(),
                        descriptiveText: NSLocalizedString("Continuous Glucose Monitor", comment: "Descriptive text for Continuous Glucose Monitor"))
        } else {
            LargeButton(action: { self.cgmChooserIsPresented = true },
                        includeArrow: false,
                        imageView: AnyView(plusImage),
                        label: NSLocalizedString("Add CGM", comment: "Title text for button to add CGM device"),
                        descriptiveText: NSLocalizedString("Tap here to set up a CGM", comment: "Descriptive text for button to add CGM device"))
                .actionSheet(isPresented: $cgmChooserIsPresented) {
                    ActionSheet(title: Text("Add CGM", comment: "The title of the CGM chooser in settings"), buttons: cgmChoices)
            }
        }
    }
    
    private var cgmChoices: [ActionSheet.Button] {
        var result = viewModel.cgmManagerSettingsViewModel.availableDevices
            .sorted(by: {$0.localizedTitle < $1.localizedTitle})
            .map { availableDevice in
                ActionSheet.Button.default(Text(availableDevice.localizedTitle)) {
                    self.viewModel.cgmManagerSettingsViewModel.didTapAdd(availableDevice)
            }
        }
        result.append(.cancel())
        return result
    }
    
    private var servicesSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Services", comment: "The title of the services section in settings"))) {
            ForEach(viewModel.servicesViewModel.activeServices().indices, id: \.self) { index in
                LargeButton(action: { self.viewModel.servicesViewModel.didTapService(index) },
                            includeArrow: true,
                            imageView: self.serviceImage(uiImage: (self.viewModel.servicesViewModel.activeServices()[index] as? ServiceUI)?.image),
                            label: self.viewModel.servicesViewModel.activeServices()[index].localizedTitle,
                            descriptiveText: "")
            }
            if viewModel.servicesViewModel.inactiveServices().count > 0 {
                LargeButton(action: { self.serviceChooserIsPresented = true },
                            includeArrow: false,
                            imageView: AnyView(plusImage),
                            label: NSLocalizedString("Add Service", comment: "The title of the add service button in settings"),
                            descriptiveText: NSLocalizedString("Tap here to set up a Service", comment: "The descriptive text of the add service button in settings"))
                    .actionSheet(isPresented: $serviceChooserIsPresented) {
                        ActionSheet(title: Text("Add Service", comment: "The title of the add service action sheet in settings"), buttons: serviceChoices)
                }
            }
        }
    }
    
    private var serviceChoices: [ActionSheet.Button] {
        var result = viewModel.servicesViewModel.inactiveServices().map { availableService in
            ActionSheet.Button.default(Text(availableService.localizedTitle)) {
                self.viewModel.servicesViewModel.didTapAddService(availableService)
            }
        }
        result.append(.cancel())
        return result
    }
    
    private var deleteDataSection: some View {
        Section {
            if viewModel.pumpManagerSettingsViewModel.isTestingDevice {
                Button(action: { self.deletePumpDataAlertIsPresented.toggle() }) {
                    HStack {
                        Spacer()
                        Text("Delete Testing Pump Data").accentColor(.destructive)
                        Spacer()
                    }
                }
                .alert(isPresented: $deletePumpDataAlertIsPresented) {
                    makeDeleteAlert(for: self.viewModel.pumpManagerSettingsViewModel)
                }
            }
            if viewModel.cgmManagerSettingsViewModel.isTestingDevice {
                Button(action: { self.deleteCGMDataAlertIsPresented.toggle() }) {
                    HStack {
                        Spacer()
                        Text("Delete Testing CGM Data").accentColor(.destructive)
                        Spacer()
                    }
                }
                .alert(isPresented: $deleteCGMDataAlertIsPresented) {
                    makeDeleteAlert(for: self.viewModel.cgmManagerSettingsViewModel)
                }
            }
        }
    }
    
    private func makeDeleteAlert<T>(for model: DeviceViewModel<T>) -> SwiftUI.Alert {
        return SwiftUI.Alert(title: Text("Delete Testing Data"),
                             message: Text("Are you sure you want to delete all your \(model.name()) Data?\n(This action is not reversible)"),
                             primaryButton: .cancel(),
                             secondaryButton: .destructive(Text("Delete"), action: model.deleteTestingDataFunc()))
    }
    
    private var supportSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Support", comment: "The title of the support section in settings"))) {
            Button(action: {
                self.viewModel.didTapIssueReport()
            }) {
                Text("Issue Report", comment: "The title text for the issue report menu item")
            }

            ForEach(pluginMenuItems.filter( { $0.section == .support })) {
                $0.view
            }

            NavigationLink(destination: CriticalEventLogExportView(viewModel: viewModel.criticalEventLogExportViewModel)) {
                Text(NSLocalizedString("Export Critical Event Logs", comment: "The title of the export critical event logs in support"))
            }
        }
    }
    
    /*
     DIY loop specific component to show users the amount of time remaining on their build before a rebuild is necessary.
     */
    private func profileExpirationSection(profileExpiration:Date) -> some View {
        let nearExpiration : Bool = ProfileExpirationAlerter.isNearProfileExpiration(profileExpiration: profileExpiration)
        let profileExpirationMsg = ProfileExpirationAlerter.createProfileExpirationSettingsMessage(profileExpiration: profileExpiration)
        let readableExpirationTime = Self.dateFormatter.string(from: profileExpiration)
        
        return Section(header: SectionHeader(label: NSLocalizedString("App Profile", comment: "Settings app profile section")),
                       footer: Text(NSLocalizedString("Profile expires ", comment: "Time that profile expires") + readableExpirationTime)) {
            if(nearExpiration) {
                Text(profileExpirationMsg).foregroundColor(.red)
            } else {
                HStack {
                    Text("Profile Expiration", comment: "Settings App Profile expiration view")
                    Spacer()
                    Text(profileExpirationMsg).foregroundColor(Color.secondary)
                }
            }
            Button(action: {
                UIApplication.shared.open(URL(string: "https://loopkit.github.io/loopdocs/build/updating/")!)
            }) {
                Text(NSLocalizedString("How to update (LoopDocs)", comment: "The title text for how to update"))
            }
        }
    }

    private static var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        return dateFormatter // formats date like "February 4, 2023 at 2:35 PM"
    }()

    private var plusImage: some View {
        Image(systemName: "plus.circle")
            .resizable()
            .scaledToFit()
            .accentColor(Color(.systemGray))
            .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
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
    
    private func serviceImage(uiImage: UIImage?) -> AnyView {
        return deviceImage(uiImage: uiImage)
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
    static let imageWidth: CGFloat = 60
    static let imageHeight: CGFloat = 60
    static let topBottomPadding: CGFloat = 10
    
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
        let displayGlucoseUnitObservable = DisplayGlucoseUnitObservable(displayGlucoseUnit: .milligramsPerDeciliter)
        let viewModel = SettingsViewModel.preview
        return Group {
            SettingsView(viewModel: viewModel, localizedAppNameAndVersion: "Loop Demo V1")
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE 2"))
                .previewDisplayName("SE light")
                .environmentObject(displayGlucoseUnitObservable)
            
            SettingsView(viewModel: viewModel, localizedAppNameAndVersion: "Loop Demo V1")
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone 11 Pro Max"))
                .previewDisplayName("11 Pro dark")
                .environmentObject(displayGlucoseUnitObservable)
        }
    }
}
