//
//  MainTabBarController.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import UIKit
import SwiftUI

/// Whether Loop shows the redesigned interface (tabs: Now, Trends, Logbook, Settings) or the classic status screen.
enum LoopInterfacePreference {
    private static let key = "com.loopkit.Loop.redesign.enabled"

    static let didChange = Notification.Name("LoopInterfacePreferenceDidChange")

    static var useRedesign: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            guard newValue != useRedesign else { return }
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

/// The redesign's root. The Now tab is Loop's own RootNavigationController, so every existing flow
/// (bolus, carbs, presets, alerts, device settings, deeplinks) keeps working from StatusTableViewController.
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate {

    let rootNavigationController: RootNavigationController
    private weak var statusTableViewController: StatusTableViewController?
    private let provider: LoopHistoryProvider
    private let settingsPlaceholder = UIViewController()

    init(rootNavigationController: RootNavigationController, statusTableViewController: StatusTableViewController, deviceManager: DeviceDataManager, loopDataManager: LoopDataManager, settingsManager: SettingsManager) {
        self.rootNavigationController = rootNavigationController
        self.statusTableViewController = statusTableViewController
        self.provider = LoopHistoryProvider(deviceManager: deviceManager, loopDataManager: loopDataManager, settingsManager: settingsManager, temporaryPresetsManager: statusTableViewController.temporaryPresetsManager)
        super.init(nibName: nil, bundle: nil)

        rootNavigationController.tabBarItem = UITabBarItem(title: NSLocalizedString("Now", comment: "Title of the Now tab in the redesigned interface, showing current glucose and Loop status"), image: UIImage(systemName: "drop.fill"), tag: 0)

        let trends = UIHostingController(rootView: TrendsView(provider: provider))
        trends.tabBarItem = UITabBarItem(title: NSLocalizedString("Trends", comment: "Title of the Trends tab in the redesigned interface"), image: UIImage(systemName: "chart.bar.fill"), tag: 1)

        let logbook = UIHostingController(rootView: LogbookView(provider: provider, deviceManager: deviceManager))
        logbook.tabBarItem = UITabBarItem(title: NSLocalizedString("Logbook", comment: "Title of the Logbook tab in the redesigned interface, listing past events"), image: UIImage(systemName: "list.bullet"), tag: 2)

        settingsPlaceholder.tabBarItem = UITabBarItem(title: NSLocalizedString("Settings", comment: "Title of the Settings tab in the redesigned interface"), image: UIImage(systemName: "gearshape.fill"), tag: 3)

        viewControllers = [rootNavigationController, trends, logbook, settingsPlaceholder]
        delegate = self
        tabBar.tintColor = UIColor(named: "accent")
        if #available(iOS 18.0, *) {
            mode = .tabBar
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Settings stays a sheet, as in classic Loop, so the tab only presents it. It is presented from the Now tab:
    /// device and service screens open from Settings through StatusTableViewController, which is only in the window
    /// while Now is selected.
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        guard viewController === settingsPlaceholder else { return true }
        showNow()
        statusTableViewController?.presentSettingsFromTab()
        return false
    }

    func showNow() {
        selectedViewController = rootNavigationController
    }

    override func restoreUserActivityState(_ activity: NSUserActivity) {
        showNow()
        rootNavigationController.restoreUserActivityState(activity)
    }
}
