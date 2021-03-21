//
//  LoopSettingsAlerter.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2020-10-28.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopCore

protocol LoopSettingsAlerterDelegate: class {
    var settings: LoopSettings { get set }
}

class LoopSettingsAlerter {

    weak var delegate: LoopSettingsAlerterDelegate?

    private let alertPresenter: AlertPresenter?
    
    let workoutOverrideReminderInterval: TimeInterval
    
    init(alertPresenter: AlertPresenter? = nil,
         workoutOverrideReminderInterval: TimeInterval = .days(1))
    {
        self.alertPresenter = alertPresenter
        self.workoutOverrideReminderInterval = workoutOverrideReminderInterval

        NotificationCenter.default.addObserver(forName: .LoopRunning, object: nil, queue: nil) {
            [weak self] _ in self?.checkAlerts()
        }
    }

    private func checkAlerts() {
        checkWorkoutOverrideReminder()
    }

    private func checkWorkoutOverrideReminder() {
        guard let indefiniteWorkoutOverrideEnabledDate = delegate?.settings.indefiniteWorkoutOverrideEnabledDate else { return }

        if  -indefiniteWorkoutOverrideEnabledDate.timeIntervalSinceNow > workoutOverrideReminderInterval {
            issueWorkoutOverrideReminder()
            // reset the date to allow the alert to be issued again after the workoutOverrideReminderInterval is surpassed
            delegate?.settings.indefiniteWorkoutOverrideEnabledDate = Date()
        }
    }

    private func issueWorkoutOverrideReminder() {
        alertPresenter?.issueAlert(workoutOverrideReminderAlert)
    }
}

// MARK: - Alerts

extension LoopSettingsAlerter {
    static var managerIdentifier = "LoopSettingsAlerter"
    
    public static var workoutOverrideReminderAlertIdentifier: Alert.Identifier {
        return Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "WorkoutOverrideReminder")
    }
    
    public var workoutOverrideReminderAlert: Alert {
        let title = NSLocalizedString("Workout Temp Adjust Still On", comment: "Workout override still on reminder alert title")
        let body = NSLocalizedString("Workout Temp Adjust has been turned on for more than 24 hours. Make sure you still want it enabled, or turn it off in the app.", comment: "Workout override still on reminder alert body.")
        let content = Alert.Content(title: title,
                                    body: body,
                                    acknowledgeActionButtonLabel: NSLocalizedString("Dismiss", comment: "Default alert dismissal"))
        return Alert(identifier: LoopSettingsAlerter.workoutOverrideReminderAlertIdentifier,
                     foregroundContent: content,
                     backgroundContent: content,
                     trigger: .immediate)
    }
}
