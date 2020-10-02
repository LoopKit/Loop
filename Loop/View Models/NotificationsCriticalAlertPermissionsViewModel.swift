//
//  NotificationsCriticalAlertPermissionsViewModel.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/5/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Combine
import Foundation
import LoopKit
import SwiftUI

public class NotificationsCriticalAlertPermissionsViewModel: ObservableObject {
    
    @Published var notificationsPermissionsGiven: Bool
    @Published var criticalAlertsPermissionsGiven: Bool

    // This is a "bridge" between old & new UI; it allows us to "combine" the two @Published variables above into
    // one published item, and also provides it in a way that may be `.assign`ed in the new UI (see `init()`) and
    // added as a `.sink` (see `SettingsTableViewController.swift`) in the old UI.
    lazy public var showWarningPublisher: AnyPublisher<Bool, Never> = {
        $notificationsPermissionsGiven
            .combineLatest($criticalAlertsPermissionsGiven)
            .map { $0 == false || $1 == false && FeatureFlags.criticalAlertsEnabled }
            .eraseToAnyPublisher()
    }()

    @Published var showWarning = false
    lazy private var cancellables = Set<AnyCancellable>()

    public init(notificationsPermissionsGiven: Bool = true, criticalAlertsPermissionsGiven: Bool = true) {
        self.notificationsPermissionsGiven = notificationsPermissionsGiven
        self.criticalAlertsPermissionsGiven = criticalAlertsPermissionsGiven
        
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) {
            [weak self] _ in
            self?.updateState()
        }
        updateState()
        
        showWarningPublisher
            .receive(on: RunLoop.main)
            .assign(to: \.showWarning, on: self)
            .store(in: &cancellables)
    }
    
    private func updateState() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsPermissionsGiven = settings.alertSetting == .enabled
                self.criticalAlertsPermissionsGiven = settings.criticalAlertSetting == .enabled
            }
        }
    }
    
    public func gotoSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}
