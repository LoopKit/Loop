//
//  StatusTableView.swift
//  Loop
//
//  Created by Cameron Ingham on 12/10/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKit
import LoopKitUI
import SwiftUI
import UIKit

private struct WrappedStatusTableViewController: UIViewControllerRepresentable {
    
    private let alertPermissionsChecker: AlertPermissionsChecker
    private let alertMuter: AlertMuter
    private let deviceDataManager: DeviceDataManager
    private let onboardingManager: OnboardingManager
    private let supportManager: SupportManager
    private let testingScenariosManager: TestingScenariosManager?
    private let settingsManager: SettingsManager
    private let temporaryPresetsManager: TemporaryPresetsManager
    private let loopDataManager: LoopDataManager
    private let diagnosticReportGenerator: DiagnosticReportGenerator
    private let simulatedData: SimulatedData
    private let analyticsServicesManager: AnalyticsServicesManager
    private let servicesManager: ServicesManager
    private let carbStore: CarbStore
    private let doseStore: DoseStore
    private let criticalEventLogExportManager: CriticalEventLogExportManager
    private let bluetoothStateManager: BluetoothStateManager
    private let statusTableViewModel: StatusTableViewModel
    
    let viewController: StatusTableViewController
    
    init(alertPermissionsChecker: AlertPermissionsChecker, alertMuter: AlertMuter, deviceDataManager: DeviceDataManager, onboardingManager: OnboardingManager, supportManager: SupportManager, testingScenariosManager: TestingScenariosManager?, settingsManager: SettingsManager, temporaryPresetsManager: TemporaryPresetsManager, loopDataManager: LoopDataManager, diagnosticReportGenerator: DiagnosticReportGenerator, simulatedData: SimulatedData, analyticsServicesManager: AnalyticsServicesManager, servicesManager: ServicesManager, carbStore: CarbStore, doseStore: DoseStore, criticalEventLogExportManager: CriticalEventLogExportManager, bluetoothStateManager: BluetoothStateManager, statusTableViewModel: StatusTableViewModel) {
        self.alertPermissionsChecker = alertPermissionsChecker
        self.alertMuter = alertMuter
        self.deviceDataManager = deviceDataManager
        self.onboardingManager = onboardingManager
        self.supportManager = supportManager
        self.testingScenariosManager = testingScenariosManager
        self.settingsManager = settingsManager
        self.temporaryPresetsManager = temporaryPresetsManager
        self.loopDataManager = loopDataManager
        self.diagnosticReportGenerator = diagnosticReportGenerator
        self.simulatedData = simulatedData
        self.analyticsServicesManager = analyticsServicesManager
        self.servicesManager = servicesManager
        self.carbStore = carbStore
        self.doseStore = doseStore
        self.criticalEventLogExportManager = criticalEventLogExportManager
        self.bluetoothStateManager = bluetoothStateManager
        self.statusTableViewModel = statusTableViewModel
        
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle(for: StatusTableViewController.self))
        let statusTableViewController = storyboard.instantiateViewController(withIdentifier: "MainStatusViewController") as! StatusTableViewController
        statusTableViewController.alertPermissionsChecker = alertPermissionsChecker
        statusTableViewController.alertMuter = alertMuter
        statusTableViewController.deviceManager = deviceDataManager
        statusTableViewController.onboardingManager = onboardingManager
        statusTableViewController.supportManager = supportManager
        statusTableViewController.testingScenariosManager = testingScenariosManager
        statusTableViewController.settingsManager = settingsManager
        statusTableViewController.temporaryPresetsManager = temporaryPresetsManager
        statusTableViewController.loopManager = loopDataManager
        statusTableViewController.diagnosticReportGenerator = diagnosticReportGenerator
        statusTableViewController.simulatedData = simulatedData
        statusTableViewController.analyticsServicesManager = analyticsServicesManager
        statusTableViewController.servicesManager = servicesManager
        statusTableViewController.carbStore = carbStore
        statusTableViewController.doseStore = doseStore
        statusTableViewController.criticalEventLogExportManager = criticalEventLogExportManager
        statusTableViewController.statusTableViewModel = statusTableViewModel
        bluetoothStateManager.addBluetoothObserver(statusTableViewController)
        
        self.viewController = statusTableViewController
    }
    
    func makeUIViewController(context: Context) -> some UIViewController {
        viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
}

struct StatusTableView: View {

    private let wrapped: WrappedStatusTableViewController
    
    var viewController: StatusTableViewController {
        wrapped.viewController
    }
    
    @ViewBuilder
    var wrappedView: some View { wrapped }
    
    @Bindable var viewModel: StatusTableViewModel
    
    init(viewModel: StatusTableViewModel) {
        self.viewModel = viewModel
        
        self.wrapped = WrappedStatusTableViewController(
            alertPermissionsChecker: viewModel.alertPermissionsChecker,
            alertMuter: viewModel.alertMuter,
            deviceDataManager: viewModel.deviceDataManager,
            onboardingManager: viewModel.onboardingManager,
            supportManager: viewModel.supportManager,
            testingScenariosManager: viewModel.testingScenariosManager,
            settingsManager: viewModel.settingsManager,
            temporaryPresetsManager: viewModel.temporaryPresetsManager,
            loopDataManager: viewModel.loopDataManager,
            diagnosticReportGenerator: viewModel.diagnosticReportGenerator,
            simulatedData: viewModel.simulatedData,
            analyticsServicesManager: viewModel.analyticsServicesManager,
            servicesManager: viewModel.servicesManager,
            carbStore: viewModel.carbStore,
            doseStore: viewModel.doseStore,
            criticalEventLogExportManager: viewModel.criticalEventLogExportManager,
            bluetoothStateManager: viewModel.bluetoothStateManager,
            statusTableViewModel: viewModel
        )
    }

    var body: some View {
        ActionTabView {
            wrappedView
                .ignoresSafeArea(edges: .bottom)
                .onChange(of: viewModel.temporaryPresetsManager.activeOverride) { _, _ in
                    Task {
                        await viewController.reloadData(animated: true)
                    }
                }
                .sheet(item: $viewModel.pendingPreset) { preset in
                    // This is the active preset; edit disabled
                    PresetDetentView(preset: preset, roundBasalRate: viewModel.loopDataManager.deliveryDelegate?.roundBasalRate, didTapEdit: { })
                        .accessibilityIdentifier("bar_Presets")
                }
        } tabs: {
            ActionTab(
                title: "Add Carbs",
                icon: "carbs",
                tintColor: .carbTintColor
            ) {
                viewController.userTappedAddCarbs()
            }
            
            ActionTab(
                title: "Bolus",
                icon: "bolus",
                tintColor: .insulinTintColor
            ) {
                viewController.presentBolusScreen()
            }
            
            ActionTab(
                title: "Presets",
                icon: viewModel.temporaryPresetsManager.activeOverride != nil
                    ? "presets-selected"
                    : "presets",
                tintColor: .presets
            ) {
                viewController.presentPresets()
            }
            
            ActionTab(
                title: "Settings",
                icon: "settings",
                tintColor: .secondaryLabel
            ) {
                viewController.presentSettings()
            }
        }
    }
}

struct ActionTab: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tintColor: UIColor
    let action: () -> Void
}

struct ActionTabBar: UIViewRepresentable {

    let items: [ActionTab]
    var isHidden: Bool = false

    func makeUIView(context: Context) -> UITabBar {
        let bar = UITabBar()
        bar.delegate = context.coordinator
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        let titleAttributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.label]
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            for state in [layout.normal, layout.selected] {
                state.titleTextAttributes = titleAttributes
            }
        }
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        return bar
    }

    func updateUIView(_ uiView: UITabBar, context: Context) {
        uiView.isHidden = isHidden
        context.coordinator.tabs = items
        uiView.items = items.enumerated().map { idx, item in
            UITabBarItem(
                title: item.title,
                image: UIImage(named: item.icon)?.scaledToFit(height: 28).withTintColor(item.tintColor, renderingMode: .alwaysOriginal),
                tag: idx
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UITabBarDelegate {
        var tabs: [ActionTab] = []

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard tabs.indices.contains(item.tag) else { return }
            tabs[item.tag].action()
            DispatchQueue.main.async {
                tabBar.selectedItem = nil
            }
        }
    }
}

private extension UIImage {
    /// Tab icons come from assets of varying raw sizes; normalize them so every
    /// tab renders at the same height.
    func scaledToFit(height: CGFloat) -> UIImage {
        guard size.height > 0, size.height != height else { return self }
        let scale = height / size.height
        let newSize = CGSize(width: size.width * scale, height: height)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

@resultBuilder
enum ActionTabBuilder {
    static func buildBlock(_ components: ActionTab...) -> [ActionTab] { components }
    static func buildOptional(_ component: [ActionTab]?) -> [ActionTab] { component ?? [] }
    static func buildEither(first component: [ActionTab]) -> [ActionTab] { component }
    static func buildEither(second component: [ActionTab]) -> [ActionTab] { component }
    static func buildArray(_ components: [[ActionTab]]) -> [ActionTab] { components.flatMap { $0 } }
}

enum ActionTabBarMetrics {

    static let barHeight: CGFloat = 49

    static var bottomSafeAreaInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
    }

    static var interfaceOrientation: UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.windows.contains { $0.isKeyWindow } }
            ?? scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
        return scene?.interfaceOrientation ?? .portrait
    }

    static var tableContentInset: CGFloat {
        guard !interfaceOrientation.isLandscape else { return 0 }
        if #available(iOS 26.0, *), bottomSafeAreaInset == 0 {
            return barHeight + 40
        }
        return 52
    }
}

struct LegacyTabBarBackground: ViewModifier {

    var isVisible: Bool = true

    func body(content: Content) -> some View {
        if !isVisible {
            content
                .frame(height: 0)
        } else if #available(iOS 26.0, *) {
            if ActionTabBarMetrics.bottomSafeAreaInset == 0 {
                content
                    .frame(height: ActionTabBarMetrics.barHeight)
                    .padding(.bottom, 16)
            } else {
                content
                    .frame(height: 0)
                    .padding(.bottom, 6)
            }
        } else {
            content
                .frame(height: ActionTabBarMetrics.barHeight)
                .background(
                    Color(UIColor.systemBackground)
                        .ignoresSafeArea(edges: .bottom)
                )
        }
    }
}

struct ActionTabView<Content: View>: View {

    @State private var orientation: UIInterfaceOrientation

    private let content: Content
    private let tabs: [ActionTab]
    
    init(
        @ViewBuilder content: @escaping () -> Content,
        @ActionTabBuilder tabs: @escaping () -> [ActionTab],
    ) {
        self.content = content()
        self.tabs = tabs()
        self.orientation = ActionTabBarMetrics.interfaceOrientation
    }

    var body: some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ActionTabBar(items: tabs, isHidden: !orientation.isPortrait)
                    .modifier(LegacyTabBarBackground(isVisible: orientation.isPortrait))
            }
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                orientation = ActionTabBarMetrics.interfaceOrientation
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                orientation = ActionTabBarMetrics.interfaceOrientation
            }
    }
}
