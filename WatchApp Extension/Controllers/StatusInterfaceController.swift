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

    @IBOutlet var carbAndBolusButtonGroup: WKInterfaceGroup!
    @IBOutlet var glucoseRangeOverrideButtonGroup: WKInterfaceGroup!

    @IBOutlet var preMealBackgroundGroup: WKInterfaceGroup!
    @IBOutlet var preMealLabel: WKInterfaceLabel!
    
    @IBOutlet var workoutBackgroundGroup: WKInterfaceGroup!
    @IBOutlet var workoutLabel: WKInterfaceLabel!

    @IBOutlet var buttonPageZeroDot: WKInterfaceGroup!
    @IBOutlet var buttonPageOneDot: WKInterfaceGroup!

    private var lastContext: WatchContext?

    private enum ButtonPage: Int {
        case carbAndBolus
        case glucoseRangeOverride
    }

    private var buttonPage: ButtonPage = .carbAndBolus

    private var preMealModeEnabled = false {
        didSet {
            if preMealModeEnabled {
                workoutModeEnabled = false
                preMealLabel.setTextColor(.carbsColor)
                preMealBackgroundGroup.setBackgroundColor(UIColor.carbsColor.withAlphaComponent(0.3))
            } else {
                preMealLabel.setTextColor(.white)
                preMealBackgroundGroup.setBackgroundColor(.darkCarbsColor)
            }
        }
    }

    private var workoutModeEnabled = false {
        didSet {
            if workoutModeEnabled {
                preMealModeEnabled = false
                workoutLabel.setTextColor(.workoutColor)
                workoutBackgroundGroup.setBackgroundColor(UIColor.workoutColor.withAlphaComponent(0.3))
            } else {
                workoutLabel.setTextColor(.white)
                workoutBackgroundGroup.setBackgroundColor(.darkWorkoutColor)
            }
        }
    }

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
        
        guard let glucose = context?.glucose,
            let unit = context?.preferredGlucoseUnit
        else {
            glucoseLabel.setHidden(true)
            eventualGlucoseLabel.setHidden(true)
            return
        }

        let formatter = NumberFormatter.glucoseFormatter(for: unit)

        if let glucoseValue = formatter.string(from: NSNumber(value: glucose.doubleValue(for: unit))){
            let trend = context?.glucoseTrend?.symbol ?? ""
            self.glucoseLabel.setText(glucoseValue + trend)
            self.glucoseLabel.setHidden(false)
        } else {
            glucoseLabel.setHidden(true)
        }

        if let eventualGlucose = context?.eventualGlucose {
            let glucoseValue = formatter.string(from: NSNumber(value: eventualGlucose.doubleValue(for: unit)))
            self.eventualGlucoseLabel.setText(glucoseValue)
            self.eventualGlucoseLabel.setHidden(false)
        } else {
            eventualGlucoseLabel.setHidden(true)
        }

        if case .preMeal? = context?.glucoseRangeScheduleOverride?.context {
            preMealModeEnabled = true
        } else {
            preMealModeEnabled = false
        }

        if case .workout? = context?.glucoseRangeScheduleOverride?.context {
            workoutModeEnabled = true
        } else {
            workoutModeEnabled = false
        }
        
        // TODO: Other elements
        statusLabel.setHidden(true)
    }

    // MARK: - Menu Items

    @IBAction func addCarbs() {
        presentController(withName: AddCarbsInterfaceController.className, context: nil)
    }

    @IBAction func setBolus() {
        presentController(withName: BolusInterfaceController.className, context: lastContext?.bolusSuggestion)
    }

    @IBAction func togglePreMealMode() {
        let context: GlucoseRangeScheduleOverrideUserInfo.Context = !preMealModeEnabled ? .preMeal : .none
        let userInfo = GlucoseRangeScheduleOverrideUserInfo(context: context, startDate: Date(), endDate: Date(timeIntervalSinceNow: .hours(1)))
        sendGlucoseRangeOverride(userInfo: userInfo)
    }

    @IBAction func toggleWorkoutMode() {
        let context: GlucoseRangeScheduleOverrideUserInfo.Context = !workoutModeEnabled ? .workout : .none
        let userInfo = GlucoseRangeScheduleOverrideUserInfo(context: context, startDate: Date(), endDate: nil)
        sendGlucoseRangeOverride(userInfo: userInfo)
    }

    private func sendGlucoseRangeOverride(userInfo: GlucoseRangeScheduleOverrideUserInfo) {
        do {
            try WCSession.default.sendGlucoseRangeScheduleOverrideMessage(userInfo,
                replyHandler: { overrideContext in
                    switch overrideContext {
                    case .preMeal:
                        self.preMealModeEnabled = true
                    case .workout:
                        self.workoutModeEnabled = true
                    case .none:
                        self.preMealModeEnabled = false
                        self.workoutModeEnabled = false
                    }
                },
                errorHandler: { error in
                    ExtensionDelegate.shared().present(error)
                }
            )
        } catch {
            presentAlert(withTitle: NSLocalizedString("Send Failed", comment: "The title of the alert controller displayed after a glucose range override send attempt fails"),
                         message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a glucose range override send attempt fails"),
                         preferredStyle: .alert,
                         actions: [WKAlertAction.dismissAction()]
            )
        }
    }

    @IBAction func swipeToPreviousButtonPage(_ sender: Any) {
        guard let previousPage = ButtonPage(rawValue: buttonPage.rawValue - 1) else {
            return
        }

        transition(from: buttonPage, to: previousPage)
        buttonPage = previousPage
    }

    @IBAction func swipeToNextButtonPage(_ sender: Any) {
        guard let nextPage = ButtonPage(rawValue: buttonPage.rawValue + 1) else {
            return
        }

        transition(from: buttonPage, to: nextPage)
        buttonPage = nextPage
    }

    private func transition(from fromPage: ButtonPage, to toPage: ButtonPage) {
        let (fromGroup, fromDot) = buttonGroupAndPageDot(forPage: fromPage)
        let (toGroup, toDot) = buttonGroupAndPageDot(forPage: toPage)

        animate(withDuration: 0.3) {
            fromGroup.setWidth(0)
            fromGroup.setAlpha(0)
            toGroup.setRelativeWidth(1, withAdjustment: 0)
            toGroup.setAlpha(1)
        }

        fromDot.setAlpha(0.4)
        toDot.setAlpha(1)
    }

    private func buttonGroupAndPageDot(forPage page: ButtonPage) -> (buttonGroup: WKInterfaceGroup, pageDot: WKInterfaceGroup) {
        switch page {
        case .carbAndBolus:
            return (carbAndBolusButtonGroup, buttonPageZeroDot)
        case .glucoseRangeOverride:
            return (glucoseRangeOverrideButtonGroup, buttonPageOneDot)
        }
    }
}
