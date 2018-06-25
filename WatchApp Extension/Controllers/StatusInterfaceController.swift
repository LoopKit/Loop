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

    @IBOutlet weak var glucoseChart: WKInterfaceImage!
    @IBOutlet weak var loopHUDImage: WKInterfaceImage!
    @IBOutlet weak var loopTimer: WKInterfaceTimer!
    @IBOutlet weak var glucoseLabel: WKInterfaceLabel!
    @IBOutlet weak var eventualGlucoseLabel: WKInterfaceLabel!
    @IBOutlet weak var iobLabel: WKInterfaceLabel!
    @IBOutlet weak var cobLabel: WKInterfaceLabel!
    @IBOutlet weak var basalLabel: WKInterfaceLabel!

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

    private var charts = StatusChartsManager()

    weak var healthManager: HealthManager?

    private var glucoseSamplesObserver: NSKeyValueObservation?

    override init() {
        super.init()

        healthManager = ExtensionDelegate.shared().healthManager

        NotificationCenter.default.addObserver(self, selector: #selector(self.glucoseUpdated), name: .GlucoseUpdated, object: nil)
    }

    @objc func glucoseUpdated() {
        DispatchQueue.main.async {
            self.updateGlucoseChart()
        }
    }

    override func didAppear() {
        super.didAppear()

        updateLoopHUD()
    }

    override func willActivate() {
        super.willActivate()

        if let healthManager = healthManager {
            if healthManager.glucoseStore.isStale {
                let userInfo = GlucoseBackfillRequestUserInfo(startDate: healthManager.glucoseStore.latestDate)
                WCSession.default.sendGlucoseBackfillRequestMessage(userInfo) { (context) in
                    healthManager.glucoseStore.backfill(samples: context.samples)
                }
            }
        }

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
        let insulinFormatter: NumberFormatter = {
            let numberFormatter = NumberFormatter()
            
            numberFormatter.numberStyle = .decimal
            numberFormatter.minimumFractionDigits = 1
            numberFormatter.maximumFractionDigits = 1
            
            return numberFormatter
        }()
        
        iobLabel.setHidden(true)
        if let activeInsulin = context?.IOB, let valueStr = insulinFormatter.string(from:NSNumber(value:activeInsulin)) {
            iobLabel.setText(String(format: NSLocalizedString(
                "IOB %1$@ U",
                comment: "The subtitle format describing units of active insulin. (1: localized insulin value description)"),
                                       valueStr))
            iobLabel.setHidden(false)
        }
        
        cobLabel.setHidden(true)
        if let carbsOnBoard = context?.COB {
            let carbFormatter = NumberFormatter()
            carbFormatter.numberStyle = .decimal
            carbFormatter.maximumFractionDigits = 0
            let valueStr = carbFormatter.string(from:NSNumber(value:carbsOnBoard))
            
            cobLabel.setText(String(format: NSLocalizedString(
                "COB %1$@ g",
                comment: "The subtitle format describing grams of active carbs. (1: localized carb value description)"),
                                      valueStr!))
            cobLabel.setHidden(false)
        }
        
        basalLabel.setHidden(true)
        if let tempBasal = context?.lastNetTempBasalDose {
            let basalFormatter = NumberFormatter()
            basalFormatter.numberStyle = .decimal
            basalFormatter.minimumFractionDigits = 1
            basalFormatter.maximumFractionDigits = 3
            basalFormatter.positivePrefix = basalFormatter.plusSign
            let valueStr = basalFormatter.string(from:NSNumber(value:tempBasal))
            
            let basalLabelText = String(format: NSLocalizedString(
                "%1$@ U/hr",
                comment: "The subtitle format describing the current temp basal rate. (1: localized basal rate description)"),
                                      valueStr!)
            basalLabel.setText(basalLabelText)
            basalLabel.setHidden(false)
        }

        updateGlucoseChart()
    }

    func updateGlucoseChart() {
        charts.historicalGlucose = healthManager?.glucoseStore.samples
        charts.predictedGlucose = lastContext?.predictedGlucose?.samples
        charts.targetRanges = lastContext?.targetRanges
        charts.temporaryOverride = lastContext?.temporaryOverride
        charts.unit = lastContext?.preferredGlucoseUnit

        self.glucoseChart.setHidden(true)
        if let chart = self.charts.glucoseChart() {
            self.glucoseChart.setImage(chart)
            self.glucoseChart.setHidden(false)
        }
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
