//
//  ActionHUDController.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import WatchConnectivity
import LoopKit


final class ActionHUDController: HUDInterfaceController {
    @IBOutlet var preMealButton: WKInterfaceButton!
    @IBOutlet var preMealButtonImage: WKInterfaceImage!
    @IBOutlet var preMealButtonBackground: WKInterfaceGroup!
    @IBOutlet var workoutButton: WKInterfaceButton!
    @IBOutlet var workoutButtonImage: WKInterfaceImage!
    @IBOutlet var workoutButtonBackground: WKInterfaceGroup!

    private lazy var preMealButtonGroup = ButtonGroup(button: preMealButton, image: preMealButtonImage, background: preMealButtonBackground, onBackgroundColor: .carbsColor, offBackgroundColor: .darkCarbsColor)

    private lazy var workoutButtonGroup = ButtonGroup(button: workoutButton, image: workoutButtonImage, background: workoutButtonBackground, onBackgroundColor: .workoutColor, offBackgroundColor: .darkWorkoutColor)

    override func willActivate() {
        super.willActivate()

        let userActivity = NSUserActivity.forViewLoopStatus()
        if #available(watchOSApplicationExtension 5.0, *) {
            update(userActivity)
        } else {
            updateUserActivity(userActivity.activityType, userInfo: userActivity.userInfo, webpageURL: nil)
        }
    }
    override func update() {
        super.update()

        let schedule = loopManager.settings.glucoseTargetRangeSchedule
        let activeOverrideContext: GlucoseRangeSchedule.Override.Context?
        if let glucoseRangeScheduleOverride = schedule?.override, glucoseRangeScheduleOverride.isActive()
        {
            activeOverrideContext = glucoseRangeScheduleOverride.context
        } else {
            activeOverrideContext = nil
        }
        updateForOverrideContext(activeOverrideContext)

        for overrideContext in GlucoseRangeSchedule.Override.Context.all {
            let contextButtonGroup = buttonGroup(for: overrideContext)
            if schedule == nil || !(schedule!.configuredOverrideContexts.contains(overrideContext)) {
                contextButtonGroup.state = .disabled
            } else if contextButtonGroup.state == .disabled {
                contextButtonGroup.state = .off
            }
        }
    }

    private func updateForOverrideContext(_ context: GlucoseRangeSchedule.Override.Context?) {
        switch context {
        case .preMeal?:
            preMealButtonGroup.state = .on
            workoutButtonGroup.turnOff()
        case .workout?:
            preMealButtonGroup.turnOff()
            workoutButtonGroup.state = .on
        case nil:
            preMealButtonGroup.turnOff()
            workoutButtonGroup.turnOff()
        }
    }

    private func buttonGroup(for overrideContext: GlucoseRangeSchedule.Override.Context) -> ButtonGroup {
        switch overrideContext {
        case .preMeal:
            return preMealButtonGroup
        case .workout:
            return workoutButtonGroup
        }
    }

    // MARK: - Menu Items

    @IBAction func togglePreMealMode() {
        guard var glucoseTargetRangeSchedule = loopManager.settings.glucoseTargetRangeSchedule else {
            return
        }
        if preMealButtonGroup.state == .on {
            glucoseTargetRangeSchedule.clearOverride()
        } else {
            guard glucoseTargetRangeSchedule.setOverride(.preMeal, until: Date(timeIntervalSinceNow: .hours(1))) else {
                return
            }
        }

        sendGlucoseRangeSchedule(glucoseTargetRangeSchedule)
    }

    @IBAction func toggleWorkoutMode() {
        guard var glucoseTargetRangeSchedule = loopManager.settings.glucoseTargetRangeSchedule else {
            return
        }
        if workoutButtonGroup.state == .on {
            glucoseTargetRangeSchedule.clearOverride()
        } else {
            guard glucoseTargetRangeSchedule.setOverride(.workout, until: .distantFuture) else {
                return
            }
        }

        sendGlucoseRangeSchedule(glucoseTargetRangeSchedule)
    }

    private var pendingMessageResponses = 0

    private func sendGlucoseRangeSchedule(_ schedule: GlucoseRangeSchedule) {
        updateForOverrideContext(schedule.override?.context)
        pendingMessageResponses += 1
        do {
            var settings = LoopSettings()
            settings.glucoseTargetRangeSchedule = schedule
            let userInfo = LoopSettingsUserInfo(settings: settings)

            try WCSession.default.sendSettingsUpdateMessage(userInfo, completionHandler: { (error) in
                DispatchQueue.main.async {
                    self.pendingMessageResponses -= 1
                    if let error = error {
                        if self.pendingMessageResponses == 0 {
                            ExtensionDelegate.shared().present(error)
                            self.updateForOverrideContext(self.loopManager.settings.glucoseTargetRangeSchedule?.override?.context)
                        }
                    } else {
                        if self.pendingMessageResponses == 0 {
                            self.loopManager.settings.glucoseTargetRangeSchedule = schedule
                        }
                    }
                }
            })
        } catch {
            pendingMessageResponses -= 1
            if pendingMessageResponses == 0 {
                updateForOverrideContext(self.loopManager.settings.glucoseTargetRangeSchedule?.override?.context)
            }
            presentAlert(
                withTitle: NSLocalizedString("Send Failed", comment: "The title of the alert controller displayed after a glucose range override send attempt fails"),
                message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a glucose range override send attempt fails"),
                preferredStyle: .alert,
                actions: [WKAlertAction.dismissAction()]
            )
        }
    }
}


extension GlucoseRangeSchedule.Override.Context {
    static let all: [GlucoseRangeSchedule.Override.Context] = [.preMeal, .workout]
}
