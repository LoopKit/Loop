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
import LoopCore


final class ActionHUDController: HUDInterfaceController {
    @IBOutlet var preMealButton: WKInterfaceButton!
    @IBOutlet var preMealButtonImage: WKInterfaceImage!
    @IBOutlet var preMealButtonBackground: WKInterfaceGroup!
    @IBOutlet var overrideButton: WKInterfaceButton!
    @IBOutlet var overrideButtonImage: WKInterfaceImage!
    @IBOutlet var overrideButtonBackground: WKInterfaceGroup!

    private lazy var preMealButtonGroup = ButtonGroup(button: preMealButton, image: preMealButtonImage, background: preMealButtonBackground, onBackgroundColor: .carbsColor, offBackgroundColor: .darkCarbsColor)

    private lazy var overrideButtonGroup = ButtonGroup(button: overrideButton, image: overrideButtonImage, background: overrideButtonBackground, onBackgroundColor: .overrideColor, offBackgroundColor: .darkOverrideColor)

    @IBOutlet var overrideButtonLabel: WKInterfaceLabel! {
        didSet {
            if FeatureFlags.sensitivityOverridesEnabled {
                overrideButtonLabel.setText(NSLocalizedString("Override", comment: "The text for the Watch button for enabling a temporary override"))
            } else {
                overrideButtonLabel.setText(NSLocalizedString("Workout", comment: "The text for the Watch button for enabling workout mode"))
            }
        }
    }

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

        if !canEnableOverride {
            overrideButtonGroup.state = .disabled
        } else if overrideButtonGroup.state == .disabled {
            overrideButtonGroup.state = .off
        }
    }

    private var canEnableOverride: Bool {
        if FeatureFlags.sensitivityOverridesEnabled {
            return !loopManager.settings.overridePresets.isEmpty
        } else {
            return loopManager.settings.legacyWorkoutTargetRange != nil
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
        case .legacyWorkout?, .preset?, .custom?:
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
            if FeatureFlags.sensitivityOverridesEnabled {
                presentController(withName: OverrideSelectionController.className, context: self as OverrideSelectionControllerDelegate)
            } else {
                let override = loopManager.settings.legacyWorkoutOverride(for: .infinity)
                sendOverride(override)
            }
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
            try WCSession.default.sendSettingsUpdateMessage(userInfo, completionHandler: { (result) in
                DispatchQueue.main.async {
                    self.pendingMessageResponses -= 1

                    switch result {
                    case .success(let context):
                        if self.pendingMessageResponses == 0 {
                            self.loopManager.settings.scheduleOverride = override
                        }

                        ExtensionDelegate.shared().loopManager.updateContext(context)
                    case .failure(let error):
                        if self.pendingMessageResponses == 0 {
                            ExtensionDelegate.shared().present(error)
                            self.updateForOverrideContext(self.loopManager.settings.scheduleOverride?.context)
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
        let override = preset.createOverride(enactTrigger: .local)
        sendOverride(override)
    }
}
