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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appName) private var appName
    @Environment(\.carbTintColor) private var carbTintColor
    @Environment(\.glucoseTintColor) private var glucoseTintColor
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.insulinTintColor) private var insulinTintColor

    @ObservedObject var viewModel: SettingsViewModel

    @State private var pumpChooserIsPresented: Bool = false
    @State private var cgmChooserIsPresented: Bool = false
    @State private var serviceChooserIsPresented: Bool = false
    @State private var therapySettingsIsPresented: Bool = false
    @State private var deletePumpDataAlertIsPresented = false
    @State private var deleteCGMDataAlertIsPresented = false

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationView {
            List {
                loopSection
                if FeatureFlags.automaticBolusEnabled {
                    dosingStrategySection
                }
                if viewModel.showWarning {
                    alertPermissionsSection
                }
                if viewModel.pumpManagerSettingsViewModel.isSetUp() {
                    therapySettingsSection
                }
                deviceSettingsSection
                if viewModel.pumpManagerSettingsViewModel.isTestingDevice || viewModel.cgmManagerSettingsViewModel.isTestingDevice {
                    deleteDataSection
                }
                if viewModel.servicesViewModel.showServices {
                    servicesSection
                }
                supportSection
            }
            .insetGroupedListStyle()
            .navigationBarTitle(Text(NSLocalizedString("Settings", comment: "Settings screen title")))
            .navigationBarItems(trailing: dismissButton)
        }
    }
    
    private var closedLoopToggleState: Binding<Bool> {
        Binding(
            get: { self.viewModel.isClosedLoopAllowed && self.viewModel.closedLoopPreference },
            set: { self.viewModel.closedLoopPreference = $0 }
        )
    }
}

extension SettingsView {
        
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Done").bold()
        }
    }
    
    private var loopSection: some View {
        Section(header: SectionHeader(label: viewModel.supportInfoProvider.localizedAppNameAndVersion)) {
            Toggle(isOn: closedLoopToggleState) {
                VStack(alignment: .leading) {
                    Text(NSLocalizedString("Closed Loop", comment: "The title text for the looping enabled switch cell"))
                    if !viewModel.isClosedLoopAllowed {
                        DescriptiveText(label: NSLocalizedString("Closed Loop requires an active CGM Sensor Session", comment: "The description text for the looping enabled switch cell when closed loop is not allowed"))
                    }
                }
            }
            .disabled(!viewModel.isClosedLoopAllowed)
        }
    }

    private var dosingStrategySection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Dosing Strategy", comment: "The title of the Dosing Strategy section in settings"))) {
            
            NavigationLink(destination: DosingStrategySelectionView(dosingStrategy: $viewModel.dosingStrategy))
            {
                HStack {
                    Text(viewModel.dosingStrategy.title)
                }
            }
        }
    }

    private var alertPermissionsSection: some View {
        Section {
            NavigationLink(destination:
                NotificationsCriticalAlertPermissionsView(mode: .flow, viewModel: viewModel.notificationsCriticalAlertPermissionsViewModel))
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
            LargeButton(action: { self.therapySettingsIsPresented = true },
                            includeArrow: true,
                            imageView: AnyView(Image("Therapy Icon")),
                            label: NSLocalizedString("Therapy Settings", comment: "Title text for button to Therapy Settings"),
                            descriptiveText: NSLocalizedString("Diabetes Treatment", comment: "Descriptive text for Therapy Settings"))
                .sheet(isPresented: $therapySettingsIsPresented) {
                    TherapySettingsView(
                        viewModel: TherapySettingsViewModel(mode: .settings,
                                                            therapySettings: self.viewModel.therapySettings(),
                                                            preferredGlucoseUnit: self.viewModel.preferredGlucoseUnit,
                                                            supportedInsulinModelSettings: self.viewModel.supportedInsulinModelSettings,
                                                            pumpSupportedIncrements: self.viewModel.pumpSupportedIncrements,
                                                            syncPumpSchedule: self.viewModel.syncPumpSchedule,
                                                            chartColors: .primary,
                                                            didSave: self.viewModel.didSave))
                        .environment(\.dismiss, self.dismiss)
                        .environment(\.appName, self.appName)
                        .environment(\.carbTintColor, self.carbTintColor)
                        .environment(\.glucoseTintColor, self.glucoseTintColor)
                        .environment(\.guidanceColors, self.guidanceColors)
                        .environment(\.insulinTintColor, self.insulinTintColor)
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
        } else {
            LargeButton(action: { self.pumpChooserIsPresented = true },
                        includeArrow: false,
                        imageView: AnyView(plusImage),
                        label: NSLocalizedString("Add Pump", comment: "Title text for button to add pump device"),
                        descriptiveText: NSLocalizedString("Tap here to set up a pump", comment: "Descriptive text for button to add pump device"))
                .actionSheet(isPresented: $pumpChooserIsPresented) {
                    ActionSheet(title: Text("Add Pump", comment: "The title of the pump chooser in settings"), buttons: pumpChoices)
            }
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
        var result = viewModel.cgmManagerSettingsViewModel.availableDevices.map { availableDevice in
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
    
    private func makeDeleteAlert(for model: DeviceViewModel) -> SwiftUI.Alert {
        return SwiftUI.Alert(title: Text("Delete Testing Data"),
                             message: Text("Are you sure you want to delete all your \(model.name()) Data?\n(This action is not reversible)"),
                             primaryButton: .cancel(),
                             secondaryButton: .destructive(Text("Delete"), action: model.deleteTestingDataFunc()))
    }
    
    private var supportSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Support", comment: "The title of the support section in settings"))) {
            NavigationLink(destination: SupportScreenView(didTapIssueReport: viewModel.didTapIssueReport,
                                                          criticalEventLogExportViewModel: viewModel.criticalEventLogExportViewModel,
                                                          activeServices: self.viewModel.activeServices,
                                                          supportInfoProvider: self.viewModel.supportInfoProvider))
            {
                Text(NSLocalizedString("Support", comment: "The title of the support item in settings"))
            }
        }
    }

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

fileprivate class FakeService1: Service {
    static var localizedTitle: String = "Service 1"
    static var serviceIdentifier: String = "FakeService1"
    var serviceDelegate: ServiceDelegate?
    var rawState: RawStateValue = [:]
    required init?(rawState: RawStateValue) {}
    convenience init() { self.init(rawState: [:])! }
    var available: AvailableService { AvailableService(identifier: serviceIdentifier, localizedTitle: localizedTitle, providesOnboarding: false) }
}
fileprivate class FakeService2: Service {
    static var localizedTitle: String = "Service 2"
    static var serviceIdentifier: String = "FakeService2"
    var serviceDelegate: ServiceDelegate?
    var rawState: RawStateValue = [:]
    required init?(rawState: RawStateValue) {}
    convenience init() { self.init(rawState: [:])! }
    var available: AvailableService { AvailableService(identifier: serviceIdentifier, localizedTitle: localizedTitle, providesOnboarding: false) }
}
fileprivate let servicesViewModel = ServicesViewModel(showServices: true,
                                                      availableServices: { [FakeService1().available, FakeService2().available] },
                                                      activeServices: { [FakeService1()] })


fileprivate class FakeClosedLoopAllowedPublisher {
    @Published var mockIsClosedLoopAllowed: Bool = false
}

public struct SettingsView_Previews: PreviewProvider {
    
    class MockSupportInfoProvider: SupportInfoProvider {
        var localizedAppNameAndVersion = "Loop v1.2"
        
        var pumpStatus: PumpManagerStatus? {
            return nil
        }
        
        var cgmDevice: HKDevice? {
            return nil
        }
        
        func generateIssueReport(completion: (String) -> Void) {
            completion("Mock Issue Report")
        }
    }
    
    public static var previews: some View {
        let fakeClosedLoopAllowedPublisher = FakeClosedLoopAllowedPublisher()
        let viewModel = SettingsViewModel(notificationsCriticalAlertPermissionsViewModel: NotificationsCriticalAlertPermissionsViewModel(),
                                          pumpManagerSettingsViewModel: DeviceViewModel(),
                                          cgmManagerSettingsViewModel: DeviceViewModel(),
                                          servicesViewModel: servicesViewModel,
                                          criticalEventLogExportViewModel: CriticalEventLogExportViewModel(exporterFactory: MockCriticalEventLogExporterFactory()),
                                          therapySettings: { TherapySettings() },
                                          supportedInsulinModelSettings: SupportedInsulinModelSettings(fiaspModelEnabled: true, walshModelEnabled: true),
                                          pumpSupportedIncrements: nil,
                                          syncPumpSchedule: nil,
                                          sensitivityOverridesEnabled: false,
                                          initialDosingEnabled: true,
                                          isClosedLoopAllowed: fakeClosedLoopAllowedPublisher.$mockIsClosedLoopAllowed,
                                          preferredGlucoseUnit: .milligramsPerDeciliter,
                                          supportInfoProvider: MockSupportInfoProvider(),
                                          activeServices: [],
                                          dosingStrategy: .automaticBolus,
                                          delegate: nil)
        return Group {
            SettingsView(viewModel: viewModel)
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE 2"))
                .previewDisplayName("SE light")
            
            SettingsView(viewModel: viewModel)
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone 11 Pro Max"))
                .previewDisplayName("11 Pro dark")
        }
    }
}
