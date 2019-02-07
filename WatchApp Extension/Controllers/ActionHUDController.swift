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
    @IBOutlet var overrideButton: WKInterfaceButton!
    @IBOutlet var overrideButtonImage: WKInterfaceImage!
    @IBOutlet var overrideButtonBackground: WKInterfaceGroup!

    private lazy var preMealButtonGroup = ButtonGroup(button: preMealButton, image: preMealButtonImage, background: preMealButtonBackground, onBackgroundColor: .carbsColor, offBackgroundColor: .darkCarbsColor)

    private lazy var overrideButtonGroup = ButtonGroup(button: overrideButton, image: overrideButtonImage, background: overrideButtonBackground, onBackgroundColor: .workoutColor, offBackgroundColor: .darkWorkoutColor)

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

        let activeOverrideContext: TemporaryScheduleOverride.Context?
        if let override = loopManager.settings.scheduleOverride, override.isActive() {
            activeOverrideContext = override.context
        } else {
            activeOverrideContext = nil
        }

        updateForOverrideContext(activeOverrideContext)

        if loopManager.settings.preMealTargetRange == nil {
            preMealButtonGroup.state = .disabled
        } else if preMealButtonGroup.state == .disabled {
            preMealButtonGroup.state = .off
        }

        if loopManager.settings.overridePresets.isEmpty {
            overrideButtonGroup.state = .disabled
        } else if overrideButtonGroup.state == .disabled {
            overrideButtonGroup.state = .off
        }
    }

    private func updateForOverrideContext(_ context: TemporaryScheduleOverride.Context?) {
        switch context {
        case nil:
            preMealButtonGroup.turnOff()
            overrideButtonGroup.turnOff()
        case .preMeal?:
            preMealButtonGroup.state = .on
            overrideButtonGroup.turnOff()
        case .preset?, .custom?:
            preMealButtonGroup.turnOff()
            overrideButtonGroup.state = .on
        }
    }

    // MARK: - Menu Items

    @IBAction func togglePreMealMode() {
        let override: TemporaryScheduleOverride?
        if preMealButtonGroup.state == .on {
            override = nil
        } else {
            override = loopManager.settings.preMealOverride(for: .hours(1))
        }

        sendOverride(override)
    }

    @IBAction func toggleOverride() {
        if overrideButtonGroup.state == .on {
            sendOverride(nil)
        } else {
            presentController(withName: OverrideSelectionController.className, context: self as OverrideSelectionControllerDelegate)
        }
    }

    private var pendingMessageResponses = 0

    private func sendOverride(_ override: TemporaryScheduleOverride?) {
        updateForOverrideContext(override?.context)
        pendingMessageResponses += 1

        var settings = LoopSettings()
        settings.scheduleOverride = override
        let userInfo = LoopSettingsUserInfo(settings: settings)
        do {
            try WCSession.default.sendSettingsUpdateMessage(userInfo, completionHandler: { error in
                DispatchQueue.main.async {
                    self.pendingMessageResponses -= 1
                    if let error = error {
                        if self.pendingMessageResponses == 0 {
                            ExtensionDelegate.shared().present(error)
                            self.updateForOverrideContext(self.loopManager.settings.scheduleOverride?.context)
                        }
                    } else {
                        if self.pendingMessageResponses == 0 {
                            self.loopManager.settings.scheduleOverride = override
                        }
                    }
                }
            })
        } catch {
            pendingMessageResponses -= 1
            if pendingMessageResponses == 0 {
                updateForOverrideContext(loopManager.settings.scheduleOverride?.context)
            }
            presentAlert(
                withTitle: NSLocalizedString("Send Failed", comment: "The title of the alert controller displayed after a glucose range override send attempt fails"),
                message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a glucose range override send attempt fails"),
                preferredStyle: .alert,
                actions: [.dismissAction()]
            )
        }
    }
}

extension ActionHUDController: OverrideSelectionControllerDelegate {
    func overrideSelectionController(_ controller: OverrideSelectionController, didSelectPreset preset: TemporaryScheduleOverridePreset) {
        let override = preset.createOverride()
        sendOverride(override)
    }
}
