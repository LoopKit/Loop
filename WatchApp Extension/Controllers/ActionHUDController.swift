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
import SwiftUI


final class ActionHUDController: HUDInterfaceController {
    @IBOutlet var preMealButton: WKInterfaceButton!
    @IBOutlet var preMealButtonImage: WKInterfaceImage!
    @IBOutlet var preMealButtonBackground: WKInterfaceGroup!
    @IBOutlet var overrideButton: WKInterfaceButton!
    @IBOutlet var overrideButtonImage: WKInterfaceImage!
    @IBOutlet var overrideButtonBackground: WKInterfaceGroup!

    private lazy var preMealButtonGroup = ButtonGroup(button: preMealButton, image: preMealButtonImage, background: preMealButtonBackground, onBackgroundColor: .carbsColor, offBackgroundColor: .darkCarbsColor, onIconColor: .darkCarbsColor, offIconColor: .carbsColor)

    private lazy var overrideButtonGroup = ButtonGroup(button: overrideButton, image: overrideButtonImage, background: overrideButtonBackground, onBackgroundColor: .overrideColor, offBackgroundColor: .darkOverrideColor, onIconColor: .darkOverrideColor, offIconColor: .overrideColor)

    @IBOutlet var overrideButtonLabel: WKInterfaceLabel! {
        didSet {
            if FeatureFlags.sensitivityOverridesEnabled {
                overrideButtonLabel.setText(NSLocalizedString("Preset", comment: "The text for the Watch button for enabling a custom preset"))
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

        updateForPreMeal(enabled: loopManager.settings.preMealOverride?.isActive() == true)
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

        glucoseFormatter.setPreferredNumberFormatter(for: loopManager.settings.glucoseUnit ?? .milligramsPerDeciliter)
    }
    
    private var canEnableOverride: Bool {
        if FeatureFlags.sensitivityOverridesEnabled {
            return !loopManager.settings.overridePresets.isEmpty
        } else {
            return loopManager.settings.legacyWorkoutTargetRange != nil
        }
    }

    private func updateForPreMeal(enabled: Bool) {
        if enabled {
            preMealButtonGroup.state = .on
        } else {
            preMealButtonGroup.turnOff()
        }
    }

    private func updateForOverrideContext(_ context: TemporaryScheduleOverride.Context?) {
        switch context {
        case nil:
            overrideButtonGroup.turnOff()
        case .preset?, .custom?:
            overrideButtonGroup.state = .on
        case .legacyWorkout?:
            preMealButtonGroup.turnOff()
            overrideButtonGroup.state = .on
        case .preMeal?:
            assertionFailure()
        }
    }

    // MARK: - Menu Items

    private var pendingMessageResponses = 0

    private let glucoseFormatter = QuantityFormatter()

    @IBAction func togglePreMealMode() {
        guard let range = loopManager.settings.preMealTargetRange else {
            return
        }
        
        let buttonToSelect = loopManager.settings.preMealOverride?.isActive() == true ? SelectedButton.on : SelectedButton.off
        let viewModel = OnOffSelectionViewModel(title: NSLocalizedString("Pre-Meal", comment: "Title for sheet to enable/disable pre-meal on watch"), message: formattedGlucoseRangeString(from: range), onSelection: setPreMealEnabled, selectedButton: buttonToSelect, selectedButtonTint: .carbsColor)
        
        presentController(withName: OnOffSelectionController.className, context: viewModel)
    }

    func setPreMealEnabled(_ isPreMealEnabled: Bool) {
        updateForPreMeal(enabled: isPreMealEnabled)
        pendingMessageResponses += 1

        var settings = loopManager.settings
        let overrideContext = settings.scheduleOverride?.context
        if isPreMealEnabled {
            settings.enablePreMealOverride(for: .hours(1))

            if !FeatureFlags.sensitivityOverridesEnabled {
                settings.clearOverride(matching: .legacyWorkout)
                updateForOverrideContext(nil)
            }
        } else {
            settings.clearOverride(matching: .preMeal)
        }

        let userInfo = LoopSettingsUserInfo(settings: settings)
        do {
            try WCSession.default.sendSettingsUpdateMessage(userInfo, completionHandler: { (result) in
                DispatchQueue.main.async {
                    self.pendingMessageResponses -= 1

                    switch result {
                    case .success(let context):
                        if self.pendingMessageResponses == 0 {
                            self.loopManager.settings.preMealOverride = settings.preMealOverride
                            self.loopManager.settings.scheduleOverride = settings.scheduleOverride
                        }

                        ExtensionDelegate.shared().loopManager.updateContext(context)
                    case .failure(let error):
                        if self.pendingMessageResponses == 0 {
                            ExtensionDelegate.shared().present(error)
                            self.updateForPreMeal(enabled: isPreMealEnabled)
                            self.updateForOverrideContext(overrideContext)
                        }
                    }
                }
            })
        } catch {
            pendingMessageResponses -= 1
            if pendingMessageResponses == 0 {
                updateForPreMeal(enabled: isPreMealEnabled)
                updateForOverrideContext(overrideContext)
                presentAlert(
                    withTitle: NSLocalizedString("Send Failed", comment: "The title of the alert controller displayed after a glucose range override send attempt fails"),
                    message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a glucose range override send attempt fails"),
                    preferredStyle: .alert,
                    actions: [.dismissAction()]
                )
            }
        }
    }

    @IBAction func toggleOverride() {
        if FeatureFlags.sensitivityOverridesEnabled {
            overrideButtonGroup.state == .on
                ? sendOverride(nil)
                : presentController(withName: OverrideSelectionController.className, context: self as OverrideSelectionControllerDelegate)
        } else if let range = loopManager.settings.legacyWorkoutTargetRange {
            let buttonToSelect = loopManager.settings.nonPreMealOverrideEnabled() == true ? SelectedButton.on : SelectedButton.off
            
            let viewModel = OnOffSelectionViewModel(
                title: NSLocalizedString("Workout", comment: "Title for sheet to enable/disable workout mode on watch"),
                message: formattedGlucoseRangeString(from: range),
                onSelection: { isWorkoutEnabled in
                    let override = isWorkoutEnabled ? self.loopManager.settings.legacyWorkoutOverride(for: .infinity) : nil
                    self.sendOverride(override)
                },
                selectedButton: buttonToSelect,
                selectedButtonTint: .glucose
            )
            presentController(withName: OnOffSelectionController.className, context: viewModel)
        }
    }

    private func formattedGlucoseRangeString(from range: DoubleRange) -> String {
        String(
            format: NSLocalizedString(
                "%1$@ – %2$@ %3$@",
                comment: "Format string for glucose range (1: lower bound)(2: upper bound)(3: unit)"
            ),
            glucoseFormatter.numberFormatter.string(from: range.minValue) ?? String(range.minValue),
            glucoseFormatter.numberFormatter.string(from: range.maxValue) ?? String(range.maxValue),
            glucoseFormatter.string(from: loopManager.settings.glucoseUnit ?? .milligramsPerDeciliter)
        )
    }

    private func sendOverride(_ override: TemporaryScheduleOverride?) {
        updateForOverrideContext(override?.context)
        pendingMessageResponses += 1

        var settings = loopManager.settings
        let isPreMealEnabled = settings.preMealOverride?.isActive() == true
        if override?.context == .legacyWorkout {
            settings.preMealOverride = nil
        }
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
                            self.loopManager.settings.preMealOverride = settings.preMealOverride
                        }

                        ExtensionDelegate.shared().loopManager.updateContext(context)
                    case .failure(let error):
                        if self.pendingMessageResponses == 0 {
                            ExtensionDelegate.shared().present(error)
                            self.updateForOverrideContext(override?.context)
                            self.updateForPreMeal(enabled: isPreMealEnabled)
                        }
                    }
                }
            })
        } catch {
            pendingMessageResponses -= 1
            if pendingMessageResponses == 0 {
                updateForOverrideContext(override?.context)
                updateForPreMeal(enabled: isPreMealEnabled)
                presentAlert(
                    withTitle: NSLocalizedString("Send Failed", comment: "The title of the alert controller displayed after a glucose range override send attempt fails"),
                    message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a glucose range override send attempt fails"),
                    preferredStyle: .alert,
                    actions: [.dismissAction()]
                )
            }
        }
    }
}

extension ActionHUDController: OverrideSelectionControllerDelegate {
    func overrideSelectionController(_ controller: OverrideSelectionController, didSelectPreset preset: TemporaryScheduleOverridePreset) {
        let override = preset.createOverride(enactTrigger: .local)
        sendOverride(override)
    }
}
