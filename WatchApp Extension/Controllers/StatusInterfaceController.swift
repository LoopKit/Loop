//
//  StatusInterfaceController.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import WatchConnectivity


final class StatusInterfaceController: WKInterfaceController, ContextUpdatable {

    @IBOutlet weak var loopHUDImage: WKInterfaceImage!
    @IBOutlet weak var loopTimer: WKInterfaceTimer!
    @IBOutlet weak var glucoseLabel: WKInterfaceLabel!
    @IBOutlet weak var eventualGlucoseLabel: WKInterfaceLabel!
    @IBOutlet weak var statusLabel: WKInterfaceLabel!

    @IBOutlet var preMealButton: WKInterfaceButton!
    @IBOutlet var preMealButtonImage: WKInterfaceImage!
    @IBOutlet var preMealButtonBackground: WKInterfaceGroup!

    @IBOutlet var workoutButton: WKInterfaceButton!
    @IBOutlet var workoutButtonImage: WKInterfaceImage!
    @IBOutlet var workoutButtonBackground: WKInterfaceGroup!

    private class ButtonGroup {
        private let button: WKInterfaceButton
        private let image: WKInterfaceImage
        private let background: WKInterfaceGroup
        private let onBackgroundColor: UIColor
        private let offBackgroundColor: UIColor

        enum State {
            case on
            case off
            case disabled
        }

        var state: State = .off {
            didSet {
                let imageTintColor: UIColor
                let backgroundColor: UIColor
                switch state {
                case .on:
                    imageTintColor = offBackgroundColor
                    backgroundColor = onBackgroundColor
                case .off:
                    imageTintColor = onBackgroundColor
                    backgroundColor = offBackgroundColor
                case .disabled:
                    imageTintColor = .disabledButtonColor
                    backgroundColor = .darkDisabledButtonColor
                }

                button.setEnabled(state != .disabled)
                image.setTintColor(imageTintColor)
                background.setBackgroundColor(backgroundColor)
            }
        }

        init(button: WKInterfaceButton, image: WKInterfaceImage, background: WKInterfaceGroup, onBackgroundColor: UIColor, offBackgroundColor: UIColor) {
            self.button = button
            self.image = image
            self.background = background
            self.onBackgroundColor = onBackgroundColor
            self.offBackgroundColor = offBackgroundColor
        }

        func turnOff() {
            switch state {
            case .on:
                state = .off
            case .off, .disabled:
                break
            }
        }
    }

    private lazy var preMealButtonGroup = ButtonGroup(button: preMealButton, image: preMealButtonImage, background: preMealButtonBackground, onBackgroundColor: .carbsColor, offBackgroundColor: .darkCarbsColor)

    private lazy var workoutButtonGroup = ButtonGroup(button: workoutButton, image: workoutButtonImage, background: workoutButtonBackground, onBackgroundColor: .workoutColor, offBackgroundColor: .darkWorkoutColor)

    private var lastOverrideContext: GlucoseRangeScheduleOverrideUserInfo.Context?

    private var lastContext: WatchContext?

    override func didAppear() {
        super.didAppear()

        updateLoopHUD()
    }

    override func willActivate() {
        super.willActivate()

        updateLoopHUD()
    }

    private func updateLoopHUD() {
        guard let date = lastContext?.loopLastRunDate else {
            return
        }

        let loopImage: LoopImage

        switch date.timeIntervalSinceNow {
        case let t where t > .minutes(-6):
            loopImage = .Fresh
        case let t where t > .minutes(-20):
            loopImage = .Aging
        default:
            loopImage = .Stale
        }

        self.loopHUDImage.setLoopImage(loopImage)
    }

    func update(with context: WatchContext?) {
        lastContext = context

        if let date = context?.loopLastRunDate {
            self.loopTimer.setDate(date)
            self.loopTimer.setHidden(false)
            self.loopTimer.start()

            updateLoopHUD()
        } else {
            loopTimer.setHidden(true)
            loopHUDImage.setLoopImage(.Unknown)
        }
        
        if let glucose = context?.glucose, let unit = context?.preferredGlucoseUnit {
            let formatter = NumberFormatter.glucoseFormatter(for: unit)

            if let glucoseValue = formatter.string(from: glucose.doubleValue(for: unit)) {
                let trend = context?.glucoseTrend?.symbol ?? ""
                self.glucoseLabel.setText(glucoseValue + trend)
                self.glucoseLabel.setHidden(false)
            } else {
                glucoseLabel.setHidden(true)
            }

            if let eventualGlucose = context?.eventualGlucose {
                let glucoseValue = formatter.string(from: eventualGlucose.doubleValue(for: unit))
                self.eventualGlucoseLabel.setText(glucoseValue)
                self.eventualGlucoseLabel.setHidden(false)
            } else {
                eventualGlucoseLabel.setHidden(true)
            }
        } else {
            glucoseLabel.setHidden(true)
            eventualGlucoseLabel.setHidden(true)
        }

        let overrideContext: GlucoseRangeScheduleOverrideUserInfo.Context?
        if let glucoseRangeScheduleOverride = context?.glucoseRangeScheduleOverride, (glucoseRangeScheduleOverride.startDate...glucoseRangeScheduleOverride.effectiveEndDate).contains(Date())
        {
            overrideContext = glucoseRangeScheduleOverride.context
        } else {
            overrideContext = nil
        }
        updateForOverrideContext(overrideContext)
        lastOverrideContext = overrideContext

        if let configuredOverrideContexts = context?.configuredOverrideContexts {
            for overrideContext in GlucoseRangeScheduleOverrideUserInfo.Context.allContexts {
                let contextButtonGroup = buttonGroup(for: overrideContext)
                if !configuredOverrideContexts.contains(overrideContext) {
                    contextButtonGroup.state = .disabled
                } else if contextButtonGroup.state == .disabled {
                    contextButtonGroup.state = .off
                }
            }
        }

        // TODO: Other elements
        statusLabel.setHidden(true)
    }

    private func updateForOverrideContext(_ context: GlucoseRangeScheduleOverrideUserInfo.Context?) {
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

    private func buttonGroup(for overrideContext: GlucoseRangeScheduleOverrideUserInfo.Context) -> ButtonGroup {
        switch overrideContext {
        case .preMeal:
            return preMealButtonGroup
        case .workout:
            return workoutButtonGroup
        }
    }

    // MARK: - Menu Items

    @IBAction func addCarbs() {
        presentController(withName: AddCarbsInterfaceController.className, context: nil)
    }

    @IBAction func setBolus() {
        presentController(withName: BolusInterfaceController.className, context: lastContext?.bolusSuggestion)
    }

    @IBAction func togglePreMealMode() {
        let userInfo: GlucoseRangeScheduleOverrideUserInfo?
        if preMealButtonGroup.state == .on {
            userInfo = nil
        } else {
            userInfo = GlucoseRangeScheduleOverrideUserInfo(context: .preMeal, startDate: Date(), endDate: Date(timeIntervalSinceNow: .hours(1)))
        }

        updateForOverrideContext(userInfo?.context)
        sendGlucoseRangeOverride(userInfo: userInfo)
    }

    @IBAction func toggleWorkoutMode() {
        let userInfo: GlucoseRangeScheduleOverrideUserInfo?
        if workoutButtonGroup.state == .on {
            userInfo = nil
        } else {
            userInfo = GlucoseRangeScheduleOverrideUserInfo(context: .workout, startDate: Date(), endDate: nil)
        }

        updateForOverrideContext(userInfo?.context)
        sendGlucoseRangeOverride(userInfo: userInfo)
    }

    private var pendingMessageResponses = 0

    private func sendGlucoseRangeOverride(userInfo: GlucoseRangeScheduleOverrideUserInfo?) {
        pendingMessageResponses += 1
        do {
            try WCSession.default.sendGlucoseRangeScheduleOverrideMessage(userInfo,
                replyHandler: { _ in
                    DispatchQueue.main.async {
                        self.pendingMessageResponses -= 1
                        if self.pendingMessageResponses == 0 {
                            self.updateForOverrideContext(userInfo?.context)
                        }
                        self.lastOverrideContext = userInfo?.context
                    }
                },
                errorHandler: { error in
                    DispatchQueue.main.async {
                        self.pendingMessageResponses -= 1
                        if self.pendingMessageResponses == 0 {
                            self.updateForOverrideContext(self.lastOverrideContext)
                        }
                        ExtensionDelegate.shared().present(error)
                    }
                }
            )
        } catch {
            pendingMessageResponses -= 1
            if pendingMessageResponses == 0 {
                updateForOverrideContext(lastOverrideContext)
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
