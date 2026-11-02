//
//  SettingsView.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/24/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
import LoopKitUI
import MockKit
import SwiftUI
import LoopUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference
    @Environment(\.dismissAction) private var dismiss
    @Environment(\.appName) private var appName
    @Environment(\.guidanceColors) private var guidanceColors
    @Environment(\.carbTintColor) private var carbTintColor
    @Environment(\.glucoseTintColor) private var glucoseTintColor
    @Environment(\.insulinTintColor) private var insulinTintColor
    @Environment(\.isInvestigationalDevice) private var isInvestigationalDevice

    @State var viewModel: SettingsViewModel
    @ObservedObject var versionUpdateViewModel: VersionUpdateViewModel

    enum Destination {
        enum Alert: String, Identifiable {
            var id: String {
                rawValue
            }
            
            case deleteCGMData
            case deletePumpData
            case deleteAllTestingData
        }
        
        enum PluginPicker: String, Identifiable {
            var id: String {
                rawValue
            }
            
            case cgmPicker
            case pumpPicker
            case watchPicker
            case servicePicker
        }
        
        enum Sheet: String, Identifiable {
            var id: String {
                rawValue
            }
            
            case favoriteFoods
            case presets
        }
    }
    
    @State private var pluginPicker: Destination.PluginPicker?
    @State private var alert: Destination.Alert?
    @State private var sheet: Destination.Sheet?
    @State private var pluginSelection: (() -> Void)?
    @State private var setupChange: SetupChange?
    
    var localizedAppNameAndVersion: String

    init(viewModel: SettingsViewModel, localizedAppNameAndVersion: String) {
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
                    if FeatureFlags.dosingStrategySelectionEnabled {
                        dosingStrategySection
                    }
                    alertManagementSection
                    statisticsSection
                    if viewModel.pumpManagerSettingsViewModel.isSetUp() {
                        therapySection
                    }
                    presetsSection
                    deviceSettingsSection
                    if offersWatchPermissions {
                        watchPermissionsSection
                    }
                    healthAccessSection
                    if FeatureFlags.allowExperimentalFeatures {
                        favoriteFoodsSection
                    }
                    if (viewModel.pumpManagerSettingsViewModel.isTestingDevice || viewModel.cgmManagerSettingsViewModel.isTestingDevice) && viewModel.showDeleteTestData {
                        deleteDataSection
                    }
                }
                Group {
                    if viewModel.servicesViewModel.showServices {
                        servicesSection
                    }

                    // Catch-all for menu items without a dedicated section (e.g. .custom).
                    // .configuration items render in the configuration section and
                    // .support items in the Support section, so exclude both to avoid
                    // showing them twice.
                    ForEach(pluginMenuItems.filter({ $0.section != .support && $0.section != .configuration })) { item in
                        item.view
                    }

                    supportSection

                    if let profileExpiration = BuildDetails.default.profileExpiration, FeatureFlags.profileExpirationSettingsViewEnabled {
                        appExpirationSection(profileExpiration: profileExpiration)
                    }
                }
            }
            .insetGroupedListStyle()
            .navigationBarTitle(Text(NSLocalizedString("Settings", comment: "Settings screen title")))
            .navigationBarItems(trailing: dismissButton)
            .fullScreenCover(item: $pluginPicker, onDismiss: {
                pluginSelection?()
                pluginSelection = nil
            }) { picker in
                pluginPickerView(for: picker)
            }
            .alert(item: $alert) { alert in
                switch alert {
                case .deleteCGMData:
                    return makeDeleteAlert(for: self.viewModel.cgmManagerSettingsViewModel)
                case .deletePumpData:
                    return makeDeleteAlert(for: self.viewModel.pumpManagerSettingsViewModel)
                case .deleteAllTestingData:
                    return SwiftUI.Alert(title: Text("Delete All Testing Data"),
                                         message: Text("Are you sure you want to delete all your testing Data?\n(This action is not reversible)"),
                                         primaryButton: .cancel(),
                                         secondaryButton: .destructive(Text("Delete"), action: viewModel.deleteAllTestingData))
                }
            }
            .sheet(item: $sheet) { sheet in
                Group {
                    switch sheet {
                    case .presets:
                        if let carbStore = viewModel.deviceManager?.carbStore, let doseStore = viewModel.deviceManager?.doseStore, let glucoseStore = viewModel.deviceManager?.glucoseStore {
                            PresetsView(
                                roundBasalRate: viewModel.deliveryDelegate?.roundBasalRate,
                                carbStore: carbStore,
                                doseStore: doseStore,
                                glucoseStore: glucoseStore,
                                trainingContent: viewModel.availableSupports.flatMap({ $0.trainingMedia(for: .presets) }),
                                automationHistory: { viewModel.delegate?.automationHistory ?? [] }
                            )
                        }
                    case .favoriteFoods:
                        FavoriteFoodsView(insightsDelegate: viewModel.favoriteFoodInsightsDelegate)
                    }
                }
                .environmentObject(displayGlucosePreference)
                .environment(\.dismissAction, self.dismiss)
                .environment(\.appName, self.appName)
                .environment(\.chartColorPalette, .primary)
                .environment(\.carbTintColor, self.carbTintColor)
                .environment(\.glucoseTintColor, self.glucoseTintColor)
                .environment(\.guidanceColors, self.guidanceColors)
                .environment(\.insulinTintColor, self.insulinTintColor)
            }
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

    private var closedLoopToggleState: Binding<Bool> {
        Binding(
            get: { self.viewModel.closedLoopPreference },
            set: { self.viewModel.closedLoopPreference = $0 }
        )
    }
}

struct PluginMenuItem<Content: View>: Identifiable {
    var id: String {
        return pluginIdentifier + String(describing: offset)
    }

    let section: SettingsMenuSection
    let view: Content
    let pluginIdentifier: String
    let offset: Int
}

extension SettingsView {
        
    private var dismissButton: some View {
        Button(action: dismiss) {
            Text("Done").bold()
        }.accessibilityIdentifier("button_done")
    }
    
    private var loopSection: some View {
        Section(
            header: Group {
                if isInvestigationalDevice {
                    Text(Image(systemName: "exclamationmark.triangle.fill"))
                        .foregroundColor(guidanceColors.warning) +
                    Text(" ") +
                    Text("CAUTION - Investigational device. Limited by Federal (or United States) law to investigational use.")
                }
            }
            .font(.footnote)
            .textCase(nil)
            .foregroundColor(.primary)
            .padding(.bottom, 6)
        ) {
            ConfirmationToggle(
                isOn: closedLoopToggleState,
                confirmOn: false,
                alertTitle: NSLocalizedString("Are you sure you want to turn automation OFF?", comment: "Closed loop alert title"),
                alertBody: NSLocalizedString("Your pump and CGM will continue operating but the app will not make automatic adjustments. You will receive your scheduled basal rate(s).", comment: "Closed loop alert message"),
                confirmAction: .init(label: { Text("Yes, turn OFF") })
            ) {
                HStack(spacing: 12) {
                    LoopCircleView(
                        closedLoop: viewModel.automaticDosingEnabled,
                        freshness: viewModel.loopStatusCircleFreshness,
                        deviceIssue: viewModel.deviceIssue
                    )
                    .frame(width: 36, height: 36)
                    .padding(12)
                    
                    VStack(alignment: .leading) {
                        Text("Closed Loop", comment: "The title text for the looping enabled switch cell")
                        DescriptiveText(label: NSLocalizedString("Insulin Automation", comment: "Closed loop settings button descriptive text"))
                        if !viewModel.isOnboardingComplete {
                            DescriptiveText(label: NSLocalizedString("Closed Loop requires Setup to be Complete", comment: "The description text for the looping enabled switch cell when onboarding is not complete"))
                        } else if let closedLoopDescriptiveText = viewModel.closedLoopDescriptiveText {
                            DescriptiveText(label: closedLoopDescriptiveText)
                        }
                    }
                }
            }
            .accessibilityIdentifier("settingsViewClosedLoopToggle")
            .disabled(!viewModel.isOnboardingComplete)
            .padding(.vertical)
        }
    }
    
    private var softwareUpdateSection: some View {
        Section(footer: Text(viewModel.versionUpdateViewModel.footer(appName: appName))) {
            NavigationLink(destination: viewModel.versionUpdateViewModel.softwareUpdateView) {
                HStack {
                    Text(NSLocalizedString("Software Update", comment: "Software update button link text"))
                    Spacer()
                    viewModel.versionUpdateViewModel.icon
                }
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
    
    @ViewBuilder
    private var alertWarning: some View {
        if viewModel.alertPermissionsChecker.showWarning || viewModel.alertPermissionsChecker.notificationCenterSettings.scheduledDeliveryEnabled {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.critical)
                .accessibilityIdentifier("settingsViewAlertManagementAlertWarning")
        } else if viewModel.alertMuter.configuration.shouldMute {
            Image(systemName: "speaker.slash.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundColor(guidanceColors.critical)
                .padding(5)
        }
    }

    private var alertManagementSection: some View {
        Section {
            NavigationLink(destination: AlertManagementView(checker: viewModel.alertPermissionsChecker, alertMuter: viewModel.alertMuter, glucoseAlertManager: viewModel.deviceManager?.glucoseAlertManager, alertStore: viewModel.deviceManager?.alertManager?.alertStore)) {
                LargeButton(
                    action: {},
                    includeArrow: false,
                    imageView: Image(systemName: "bell.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30),
                    secondaryImageView: alertWarning,
                    label: NSLocalizedString("Alert Management", comment: "Alert Permissions button text"),
                    descriptiveText: NSLocalizedString("iOS Permissions and Mute All App Sounds", comment: "Alert Permissions descriptive text")
                )
                .accessibilityIdentifier("settingsViewAlertManagement")
            }
            NavigationLink(destination: LiveActivityManagementView()) {
                LargeButton(
                    action: {},
                    includeArrow: false,
                    imageView: Image(systemName: "rectangle.on.rectangle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30),
                    label: NSLocalizedString("Live Activity", comment: "Live Activity settings button text"),
                    descriptiveText: NSLocalizedString("Lock Screen, Dynamic Island, and CarPlay display", comment: "Live Activity settings descriptive text")
                )
                .accessibilityIdentifier("settingsViewLiveActivity")
            }
            NavigationLink(destination: DisplaySettingsView()) {
                LargeButton(
                    action: {},
                    includeArrow: false,
                    imageView: Image(systemName: "chart.line.uptrend.xyaxis")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30),
                    label: NSLocalizedString("Display", comment: "Display settings button text"),
                    descriptiveText: NSLocalizedString("Chart scale, time window and now line", comment: "Display settings descriptive text")
                )
            }
        }
    }

    @ViewBuilder
    private var statisticsSection: some View {
        if let glucoseStore = viewModel.deviceManager?.glucoseStore {
            Section {
                NavigationLink(destination: StatisticsView(
                    glucoseStore: glucoseStore,
                    insulinDeliveryHistory: viewModel.insulinDeliveryHistory,
                    scheduledBasalTotal: viewModel.therapySettings().basalRateSchedule?.total()
                )) {
                    LargeButton(
                        action: {},
                        includeArrow: false,
                        imageView: Image(systemName: "chart.xyaxis.line")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30),
                        label: NSLocalizedString("Statistics", comment: "Statistics settings button text"),
                        descriptiveText: NSLocalizedString("Glucose overview, ambulatory glucose profile and daily insulin", comment: "Statistics settings descriptive text")
                    )
                    .accessibilityIdentifier("settingsViewStatistics")
                }
                NavigationLink(destination: CurrentSetupView(viewModel: CurrentSetupViewModel(
                    selected: setupChange,
                    loadHistory: { [viewModel] in try await viewModel.setupHistory?() ?? SetupHistory(settings: [], experiments: []) },
                    glucoseStore: glucoseStore,
                    insulinDeliveryHistory: viewModel.insulinDeliveryHistory,
                    outcomesPackageBuilder: viewModel.outcomesPackageBuilder
                ))) {
                    LargeButton(
                        action: {},
                        includeArrow: false,
                        imageView: Image(systemName: "clock.arrow.circlepath")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 30),
                        label: NSLocalizedString("Current Setup", comment: "Current setup settings button text"),
                        descriptiveText: currentSetupDescriptiveText
                    )
                    .accessibilityIdentifier("settingsViewCurrentSetup")
                }
                .task {
                    setupChange = try? await viewModel.setupHistory?().latest
                }
            }
        }
    }

    private var currentSetupDescriptiveText: String {
        guard let setupChange else {
            return NSLocalizedString("How long your settings have been unchanged", comment: "Current setup settings descriptive text before the setup is known")
        }
        guard let item = setupChange.items.first else {
            return setupChange.durationDescription
        }
        let changed = setupChange.isInitialSetup ? setupChange.itemsDescription : setupChange.items.count > 1
            ? String(format: NSLocalizedString("%@ and more", comment: "Several settings changed together (1: the first one)"), item.title)
            : item.title
        return String(format: NSLocalizedString("%1$@ · Last change: %2$@", comment: "Current setup settings descriptive text (1: time since the last change, 2: what changed)"), setupChange.durationDescription, changed)
    }

    private func healthKitSharingStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        viewModel.deviceManager?.healthKitSharingStatus(for: type) ?? .notDetermined
    }

    @ViewBuilder
    private var healthAccessWarning: some View {
        let denied = healthKitSharingStatus(for: HealthKitSampleStore.glucoseType) == .sharingDenied
            || healthKitSharingStatus(for: HealthKitSampleStore.insulinQuantityType) == .sharingDenied
        if denied {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.critical)
                .accessibilityIdentifier("settingsViewHealthAccessWarning")
        }
    }

    private var healthAccessSection: some View {
        Section {
            NavigationLink(destination: HealthAccessView(
                glucoseSharingStatus: { healthKitSharingStatus(for: HealthKitSampleStore.glucoseType) },
                insulinSharingStatus: { healthKitSharingStatus(for: HealthKitSampleStore.insulinQuantityType) },
                carbSharingStatus: { healthKitSharingStatus(for: HealthKitSampleStore.carbType) }
            )) {
                LargeButton(
                    action: {},
                    includeArrow: false,
                    imageView: Image(systemName: "heart.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30),
                    secondaryImageView: healthAccessWarning,
                    label: NSLocalizedString("Apple Health", comment: "Apple Health settings button text"),
                    descriptiveText: NSLocalizedString("Glucose, Insulin, and Carb Data Access", comment: "Apple Health settings descriptive text")
                )
                .accessibilityIdentifier("settingsViewHealthAccess")
            }
        }
    }

    private var therapySettingsView: some View {
        TherapySettingsView(
            mode: .settings,
            viewModel: TherapySettingsViewModel(
                therapySettings: viewModel.therapySettings(),
                delegate: viewModel.therapySettingsViewModelDelegate
            )
        )
        .environmentObject(displayGlucosePreference)
        .environment(\.dismissAction, self.dismiss)
        .environment(\.appName, self.appName)
        .environment(\.chartColorPalette, .primary)
        .environment(\.carbTintColor, self.carbTintColor)
        .environment(\.glucoseTintColor, self.glucoseTintColor)
        .environment(\.guidanceColors, self.guidanceColors)
        .environment(\.insulinTintColor, self.insulinTintColor)
    }

    private var therapySection: some View {
        Section {
            NavigationLink(destination: therapySettingsView) {
                LargeButton(action: {},
                            includeArrow: false,
                            imageView: Image("Therapy Icon"),
                            label: NSLocalizedString("Therapy Settings", comment: "Title text for button to Therapy Settings"),
                            descriptiveText: NSLocalizedString("Diabetes Treatment", comment: "Descriptive text for Therapy Settings"))
                .accessibilityIdentifier("button_TherapySettings")
            }

            ForEach(pluginMenuItems.filter {$0.section == .configuration}) { item in
                item.view
            }

            if FeatureFlags.allowAlgorithmExperiments {
                algorithmExperimentsSection
            }
        }
    }

    private var presetsSection: some View {
        Section {
            LargeButton(
                action: { sheet = .presets },
                includeArrow: true,
                imageView: Image("Presets Icon"),
                label: NSLocalizedString("Presets", comment: "Title text for button to Preset Settings"),
                descriptiveText: NSLocalizedString("Temporary Settings Adjustments", comment: "Descriptive text for Preset Settings")
            ).accessibilityIdentifier("button_Presets")
        }
    }

    private var pluginMenuItems: [PluginMenuItem<some View>] {
        self.viewModel.availableSupports.flatMap { plugin in
            plugin.configurationMenuItems().enumerated().map { index, item in
                PluginMenuItem(section: item.section, view: item.view, pluginIdentifier: plugin.pluginIdentifier, offset: index)
            }
        }
    }

    private var deviceSettingsSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Devices", comment: ""))) {
            pumpSection
                .accessibilityIdentifier("settingsViewInsulinPump")
            
            cgmSection
                .accessibilityIdentifier("settingsViewCGM")

            watchSection
                .accessibilityIdentifier("settingsViewWatch")
        }
    }
    
    /// Watch Permissions appear only when the watch plugin offers a remote action
    /// (`.remoteMute`, `.remoteBolus`, `.remoteCarbs`, `.remoteOverride`). No plugin does yet, so the
    /// screen stays hidden; it is kept compiled for when one does.
    private var offersWatchPermissions: Bool {
        let _ = viewModel.smartwatchManagerRevision
        guard let manager = viewModel.deviceManager?.smartwatchManager else {
            return false
        }
        return !manager.effectiveCapabilities.isDisjoint(with: [.remoteMute, .remoteBolus, .remoteCarbs, .remoteOverride])
    }

    /// Opens what the watch may ask Loop to do.
    private var watchPermissionsSection: some View {
        Section {
            NavigationLink(destination: WatchPermissionsView()) {
                LargeButton(
                    action: {},
                    includeArrow: false,
                    imageView: Image(systemName: "hand.raised.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30),
                    label: NSLocalizedString("Watch Permissions", comment: "Watch permissions button text"),
                    descriptiveText: NSLocalizedString("What the watch may ask Loop to do", comment: "Watch permissions descriptive text")
                )
                .accessibilityIdentifier("settingsViewWatchPermissions")
            }
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
            LargeButton(action: { pluginPicker = .pumpPicker },
                        includeArrow: false,
                        imageView: plusImage,
                        label: NSLocalizedString("Add Pump", comment: "Title text for button to add pump device"),
                        descriptiveText: NSLocalizedString("Tap here to set up a pump", comment: "Descriptive text for button to add pump device"))
        }
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
            LargeButton(action: { pluginPicker = .cgmPicker },
                        includeArrow: false,
                        imageView: plusImage,
                        label: NSLocalizedString("Add CGM", comment: "Title text for button to add CGM device"),
                        descriptiveText: NSLocalizedString("Tap here to set up a CGM", comment: "Descriptive text for button to add CGM device"))
        }
    }
    
    /// Only shown when a watch plugin is installed or set up.
    @ViewBuilder
    private var watchSection: some View {
        let _ = viewModel.smartwatchManagerRevision
        if viewModel.smartwatchManagerSettingsViewModel.isSetUp() {
            LargeButton(action: self.viewModel.smartwatchManagerSettingsViewModel.didTap,
                        includeArrow: true,
                        imageView: deviceImage(uiImage: viewModel.smartwatchManagerSettingsViewModel.image()),
                        label: viewModel.smartwatchManagerSettingsViewModel.name(),
                        descriptiveText: NSLocalizedString("Watch", comment: "Descriptive text for a watch plugin in Settings → Devices"))
        } else if !viewModel.smartwatchManagerSettingsViewModel.availableDevices.isEmpty {
            LargeButton(action: { pluginPicker = .watchPicker },
                        includeArrow: false,
                        imageView: plusImage,
                        label: NSLocalizedString("Add Watch", comment: "Title text for button to add a watch device"),
                        descriptiveText: NSLocalizedString("Tap here to set up a watch", comment: "Descriptive text for button to add a watch device"))
        }
    }

    private var favoriteFoodsSection: some View {
        Section {
            LargeButton(action: { sheet = .favoriteFoods },
                        includeArrow: true,
                        imageView: Image("Favorite Foods Icon").renderingMode(.template).foregroundColor(carbTintColor),
                        label: "Favorite Foods",
                        descriptiveText: "Simplify Carb Entry")
        }
    }
    
    @ViewBuilder
    private func pluginPickerView(for picker: Destination.PluginPicker) -> some View {
        switch picker {
        case .pumpPicker:
            PluginPickerView(
                pluginType: .pump,
                items: viewModel.pumpManagerSettingsViewModel.availableDevices.map { PluginPickerView.Item($0) },
                onSelect: { item in
                    if let device = viewModel.pumpManagerSettingsViewModel.availableDevices.first(where: { $0.identifier == item.id }) {
                        pluginSelection = { viewModel.pumpManagerSettingsViewModel.didTapAdd(device) }
                    }
                    pluginPicker = nil
                },
                onCancel: { pluginPicker = nil }
            )
        case .cgmPicker:
            PluginPickerView(
                pluginType: .cgm,
                items: viewModel.cgmManagerSettingsViewModel.availableDevices.map { PluginPickerView.Item($0) },
                onSelect: { item in
                    if let device = viewModel.cgmManagerSettingsViewModel.availableDevices.first(where: { $0.identifier == item.id }) {
                        pluginSelection = { viewModel.cgmManagerSettingsViewModel.didTapAdd(device) }
                    }
                    pluginPicker = nil
                },
                onCancel: { pluginPicker = nil }
            )
        case .watchPicker:
            PluginPickerView(
                pluginType: .watch,
                items: viewModel.smartwatchManagerSettingsViewModel.availableDevices.map { PluginPickerView.Item($0) },
                onSelect: { item in
                    if let device = viewModel.smartwatchManagerSettingsViewModel.availableDevices.first(where: { $0.identifier == item.id }) {
                        pluginSelection = { viewModel.smartwatchManagerSettingsViewModel.didTapAdd(device) }
                    }
                    pluginPicker = nil
                },
                onCancel: { pluginPicker = nil }
            )
        case .servicePicker:
            PluginPickerView(
                pluginType: .service,
                items: viewModel.servicesViewModel.inactiveServices().map { PluginPickerView.Item($0) },
                onSelect: { item in
                    if let service = viewModel.servicesViewModel.inactiveServices().first(where: { $0.identifier == item.id }) {
                        pluginSelection = { viewModel.servicesViewModel.didTapAddService(service) }
                    }
                    pluginPicker = nil
                },
                onCancel: { pluginPicker = nil }
            )
        }
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
                LargeButton(action: { pluginPicker = .servicePicker },
                            includeArrow: false,
                            imageView: plusImage,
                            label: NSLocalizedString("Add Service", comment: "The title of the add service button in settings"),
                            descriptiveText: NSLocalizedString("Tap here to set up a Service", comment: "The descriptive text of the add service button in settings"))
            }
        }
    }

    private var deleteDataSection: some View {
        Section {
            if viewModel.pumpManagerSettingsViewModel.isTestingDevice {
                Button(action: { alert = .deletePumpData }) {
                    HStack {
                        Spacer()
                        Text("Delete Testing Pump Data").accentColor(.destructive)
                        Spacer()
                    }
                }
            }
            if viewModel.cgmManagerSettingsViewModel.isTestingDevice {
                Button(action: { alert = .deleteCGMData }) {
                    HStack {
                        Spacer()
                        Text("Delete Testing CGM Data").accentColor(.destructive)
                        Spacer()
                    }
                }
            }
            if viewModel.cgmManagerSettingsViewModel.isTestingDevice,
               viewModel.pumpManagerSettingsViewModel.isTestingDevice
            {
                Button(action: { alert = .deleteAllTestingData }) {
                    HStack {
                        Spacer()
                        Text("Delete All Testing Data").accentColor(.destructive)
                        Spacer()
                    }
                }
            }
        }
    }
    
    private func makeDeleteAlert<T>(for model: DeviceViewModel<T>) -> SwiftUI.Alert {
        return SwiftUI.Alert(title: Text("Delete Testing Data"),
                             message: Text("Are you sure you want to delete all your \(model.name()) Data?\n(This action is not reversible)", comment: "Confirmation before you delete all your Simulated Test Devices data"),
                             primaryButton: .cancel(),
                             secondaryButton: .destructive(Text("Delete"), action: model.deleteTestingDataFunc()))
    }
    
    private var supportSection: some View {
        Section(header: SectionHeader(label: NSLocalizedString("Support", comment: "The title of the support section in settings"))) {
            ForEach(pluginMenuItems.filter( { $0.section == .support })) {
                $0.view
            }

            supportInfoRow(NSLocalizedString("Version", comment: "Label for the app version row in the Support section"), value: Text(localizedAppNameAndVersion))

            if let branch = BuildDetails.default.workspaceGitBranch ?? BuildDetails.default.gitBranch {
                supportInfoRow(NSLocalizedString("Branch", comment: "Label for the git branch row in the Support section"), value: Text(branch))
            }

            if let revision = BuildDetails.default.workspaceGitRevision ?? BuildDetails.default.gitRevision {
                supportInfoRow(NSLocalizedString("Revision", comment: "Label for the git revision row in the Support section"), value: Text(revision))
            }

            if !BuildDetails.default.customizations.isEmpty {
                supportInfoRow(NSLocalizedString("Customizations", comment: "Label for the build customizations row in the Support section"), value: Text(BuildDetails.default.customizations.joined(separator: ", ")))
            }

            supportInfoRow(NSLocalizedString("Launched", comment: "Label for the app launch time row in the Support section"), value: Text(Self.launchDate.formatted(date: .abbreviated, time: .shortened)))

            supportInfoRow(NSLocalizedString("Running For", comment: "Label for the time since app launch row in the Support section"), value: Text(Self.launchDate, style: .relative))
        }
    }

    private func supportInfoRow(_ label: String, value: Text) -> some View {
        HStack {
            Text(label)
            Spacer()
            value
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static let launchDate: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            return Date()
        }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }()
    
    /*
     DIY loop specific component to show users the amount of time remaining on their build before a rebuild is necessary.
     */
    private func appExpirationSection(profileExpiration: Date) -> some View {
        let expirationDate = AppExpirationAlerter.calculateExpirationDate(profileExpiration: profileExpiration)
        let isTestFlight = AppExpirationAlerter.isTestFlightBuild()
        let nearExpiration = AppExpirationAlerter.isNearExpiration(expirationDate: expirationDate)
        let profileExpirationMsg = AppExpirationAlerter.createProfileExpirationSettingsMessage(expirationDate: expirationDate)
        let readableExpirationTime = Self.dateFormatter.string(from: expirationDate)
        
        if isTestFlight {
            return createAppExpirationSection(
                headerLabel: NSLocalizedString("TestFlight", comment: "Settings app TestFlight section"),
                footerLabel: NSLocalizedString("TestFlight expires ", comment: "Time that build expires") + readableExpirationTime,
                expirationLabel: NSLocalizedString("TestFlight Expiration", comment: "Settings TestFlight expiration view"),
                updateURL: "https://loopkit.github.io/loopdocs/gh-actions/gh-update/",
                nearExpiration: nearExpiration,
                expirationMessage: profileExpirationMsg
            )
        } else {
            return createAppExpirationSection(
                headerLabel: NSLocalizedString("App Profile", comment: "Settings app profile section"),
                footerLabel: NSLocalizedString("Profile expires ", comment: "Time that profile expires") + readableExpirationTime,
                expirationLabel: NSLocalizedString("Profile Expiration", comment: "Settings App Profile expiration view"),
                updateURL: "https://loopkit.github.io/loopdocs/build/updating/",
                nearExpiration: nearExpiration,
                expirationMessage: profileExpirationMsg
            )
        }
    }
    
    private func createAppExpirationSection(headerLabel: String, footerLabel: String, expirationLabel: String, updateURL: String, nearExpiration: Bool, expirationMessage: String) -> some View {
        return Section(
            header: SectionHeader(label: headerLabel),
            footer: Text(footerLabel)
        ) {
            if nearExpiration {
                Text(expirationMessage).foregroundColor(.red)
            } else {
                HStack {
                    Text(expirationLabel)
                    Spacer()
                    Text(expirationMessage).foregroundColor(Color.secondary)
                }
            }
            Button(action: {
                UIApplication.shared.open(URL(string: updateURL)!)
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
    
    @ViewBuilder
    private func deviceImage(uiImage: UIImage?) -> some View {
        if let uiImage = uiImage {
            Image(uiImage: uiImage)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        } else {
            Spacer()
        }
    }
    
    @ViewBuilder
    private func serviceImage(uiImage: UIImage?) -> some View {
        deviceImage(uiImage: uiImage)
    }
}  // end extension SettingsView

// MARK: - LargeButton

fileprivate struct LargeButton<Content: View, SecondaryContent: View>: View {
    
    let action: () -> Void
    var includeArrow: Bool
    let imageView: Content
    let secondaryImageView: SecondaryContent
    let label: String
    let descriptiveText: String
    
    init(
        action: @escaping () -> Void,
        includeArrow: Bool = true,
        imageView: Content,
        secondaryImageView: SecondaryContent = EmptyView(),
        label: String,
        descriptiveText: String
    ) {
        self.action = action
        self.includeArrow = includeArrow
        self.imageView = imageView
        self.secondaryImageView = secondaryImageView
        self.label = label
        self.descriptiveText = descriptiveText
    }

    // TODO: The design doesn't show this, but do we need to consider different values here for different size classes?
    private let spacing: CGFloat = 15
    private let imageWidth: CGFloat = 60
    private let imageHeight: CGFloat = 60
    private let secondaryImageWidth: CGFloat = 30
    private let secondaryImageHeight: CGFloat = 30
    private let topBottomPadding: CGFloat = 10
    
    public var body: some View {
        Button(action: action) {
            HStack {
                HStack(spacing: spacing) {
                    imageView.frame(maxWidth: imageWidth, maxHeight: imageHeight)
                    VStack(alignment: .leading) {
                        Text(label)
                            .foregroundColor(.primary)
                        DescriptiveText(label: descriptiveText)
                    }
                }
                
                if !(secondaryImageView is EmptyView) || includeArrow {
                    Spacer()
                }
                
                if !(secondaryImageView is EmptyView) {
                    secondaryImageView.frame(width: secondaryImageWidth, height: secondaryImageHeight)
                }
                
                if includeArrow {
                    // TODO: Ick. I can't use a NavigationLink because we're not Navigating, but this seems worse somehow.
                    Image(systemName: "chevron.right").foregroundColor(.gray).font(.footnote)
                }
            }
            .padding(EdgeInsets(top: topBottomPadding, leading: 0, bottom: topBottomPadding, trailing: 0))
        }
    }
}

public struct SettingsView_Previews: PreviewProvider {
        
    public static var previews: some View {
        let displayGlucosePreference = DisplayGlucosePreference(displayGlucoseUnit: .milligramsPerDeciliter)
        let viewModel = SettingsViewModel.preview
        return Group {
            SettingsView(viewModel: viewModel, localizedAppNameAndVersion: "Loop Demo V1")
                .colorScheme(.light)
                .previewDevice(PreviewDevice(rawValue: "iPhone SE 2"))
                .previewDisplayName("SE light")
                .environmentObject(displayGlucosePreference)
            
            SettingsView(viewModel: viewModel, localizedAppNameAndVersion: "Loop Demo V1")
                .colorScheme(.dark)
                .previewDevice(PreviewDevice(rawValue: "iPhone 11 Pro Max"))
                .previewDisplayName("11 Pro dark")
                .environmentObject(displayGlucosePreference)
        }
    }
}

enum DisplayPreference {
    static let nowLine = "DisplayNowLine"
    static let fixedGlucoseScale = "DisplayFixedGlucoseScale"
    static let historyHours = "DisplayHistoryHours"
}

struct DisplaySettingsView: View {
    @AppStorage(DisplayPreference.nowLine) private var nowLine = false
    @AppStorage(DisplayPreference.fixedGlucoseScale) private var fixedGlucoseScale = false
    @AppStorage(DisplayPreference.historyHours) private var historyHours = 0
    @EnvironmentObject private var displayGlucosePreference: DisplayGlucosePreference

    private var fixedScaleRange: String {
        let values = GlucoseChart.fixedScaleAxisValues(for: displayGlucosePreference.unit)
        let formatter = displayGlucosePreference.formatter.numberFormatter
        return "\(formatter.string(from: values.first! as NSNumber) ?? "")–\(formatter.string(from: values.last! as NSNumber) ?? "")"
    }

    var body: some View {
        List {
            Section(footer: Text("A vertical line marking the current time on each chart.")) {
                Toggle("Now Line", isOn: $nowLine)
            }
            Section(header: Text("Glucose Scale"), footer: Text("Fixed keeps the glucose chart at \(fixedScaleRange) \(displayGlucosePreference.unit.localizedShortUnitString) so every glance uses the same scale. Auto zooms to fit recent and forecast glucose.")) {
                Picker("Glucose Scale", selection: $fixedGlucoseScale) {
                    Text("Auto").tag(false)
                    Text("Fixed \(fixedScaleRange)").tag(true)
                }
                .pickerStyle(.segmented)
            }
            Section(header: Text("Time Window"), footer: Text("The full forecast covers your insulin action time.")) {
                Picker("Time Window", selection: $historyHours) {
                    timeWindowRow("Full Forecast", detail: "As much history as fits").tag(0)
                    timeWindowRow("3 Hours", detail: "3 h back, 3 h ahead").tag(3)
                    timeWindowRow("6 Hours", detail: "6 h back, full forecast").tag(6)
                    timeWindowRow("12 Hours", detail: "12 h back, full forecast").tag(12)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .insetGroupedListStyle()
        .navigationTitle("Display")
    }

    private func timeWindowRow(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            Text(detail).font(.footnote).foregroundColor(.secondary)
        }
    }
}

/// What the watch may ask Loop to do. Each request is refused unless its
/// toggle is on, and the watch plugin must declare the matching capability.
private struct WatchPermissionsView: View {
    @Environment(\.appName) private var appName
    @AppStorage(UserDefaults.allowWatchMuteKey) private var allowWatchMute = false
    @AppStorage(UserDefaults.allowWatchCarbsKey) private var allowWatchCarbs = false
    @AppStorage(UserDefaults.allowWatchBolusKey) private var allowWatchBolus = false
    @AppStorage(UserDefaults.allowWatchOverridesKey) private var allowWatchOverrides = false

    var body: some View {
        List {
            Section(footer: Text(String(format: NSLocalizedString("Mutes all %1$@ sounds for as long as the watch asks, rounded up to one of the app's mute durations, the same as Mute All App Sounds, including critical alerts.", comment: "Footer for Allow Mute from Watch (1: app name)"), appName))) {
                Toggle(NSLocalizedString("Allow Mute from Watch", comment: "Toggle allowing a watch to mute the app's alerts"), isOn: $allowWatchMute)
            }

            Section(footer: Text(String(format: NSLocalizedString("%1$@ starts the preset picked on the watch, for the preset's own duration, or ends the running one, like a remote override.", comment: "Footer for Allow Presets from Watch (1: app name)"), appName))) {
                Toggle(NSLocalizedString("Allow Presets from Watch", comment: "Toggle allowing a watch to start and end override presets"), isOn: $allowWatchOverrides)
            }

            Section(footer: Text(String(format: NSLocalizedString("%1$@ adds the watch's carb entry like a remote carb entry, at most one every 15 minutes. In closed loop, %1$@ may dose for it.", comment: "Footer for Allow Carbs from Watch (1: app name)"), appName))) {
                Toggle(NSLocalizedString("Allow Carbs from Watch", comment: "Toggle allowing carb entries requested from a watch plugin"), isOn: $allowWatchCarbs)
            }

            // SmartwatchBolusPolicy checks every request.
            Section(footer: Text(String(format: NSLocalizedString("%1$@ delivers a bolus requested on the watch only within your maximum bolus and at most one every 15 minutes, and never more than the current recommendation unless the watch marks the request as forced.", comment: "Footer for Allow Boluses from Watch (1: app name)"), appName))) {
                Toggle(NSLocalizedString("Allow Boluses from Watch", comment: "Toggle allowing boluses requested from a watch plugin"), isOn: $allowWatchBolus)
            }
        }
        .insetGroupedListStyle()
        .navigationTitle(NSLocalizedString("Watch Permissions", comment: "Watch permissions screen title"))
        .onChange(of: [allowWatchMute, allowWatchOverrides, allowWatchCarbs, allowWatchBolus]) {
            NotificationCenter.default.post(name: .WatchPermissionsChanged, object: nil)
        }
    }
}
