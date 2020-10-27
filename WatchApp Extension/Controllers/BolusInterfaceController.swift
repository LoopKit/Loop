//
//  BolusInterfaceController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopCore
import WatchKit
import Foundation
import WatchConnectivity


final class BolusInterfaceController: WKInterfaceController, IdentifiableClass {

    fileprivate enum State {
        case picker
        case pickerFadeOut
        case confirmFadeIn
        case confirm
    }

    private var state: State = .picker {
        didSet {
            let durationMS = 400 // ms
            let duration: TimeInterval = 0.4 // s

            switch (oldValue, state) {
            case (.picker, .pickerFadeOut):
                bolusConfirmationInterfaceScene.setHidden(false)
                bolusConfirmationHelpText.setHidden(false)

                animate(withDuration: duration) {
                    self.recommendedValueLabel.setAlpha(0)
                    self.decrementButton.setAlpha(0)
                    self.incremementButton.setAlpha(0)
                    self.bolusButton.setAlpha(0)

                    // Smaller devices can't fit the unit label
                    if WKInterfaceDevice.current().screenBounds.height < 175 {
                        self.unitLabel.setAlpha(0)
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(durationMS)) {
                    self.state = .confirmFadeIn
                }
            case (.pickerFadeOut, .confirmFadeIn):
                animate(withDuration: duration) {
                    self.bolusConfirmationInterfaceScene.setAlpha(1)
                    self.bolusConfirmationHelpText.setAlpha(1)
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(durationMS)) {
                    self.state = .confirm
                }
            case (.confirmFadeIn, .confirm):
                self.recommendedValueLabel.setHidden(true)
                self.decrementButton.setHidden(true)
                self.incremementButton.setHidden(true)
                self.bolusButton.setHidden(true)
            default:
                assertionFailure("Illegal transition from \(oldValue) -> \(state)")
                break
            }
        }
    }

    // MARK: - Interface

    /// 1.25
    @IBOutlet weak var valueLabel: WKInterfaceLabel!

    /// REC: 2.25 U
    @IBOutlet weak var recommendedValueLabel: WKInterfaceLabel!

    @IBOutlet weak var unitLabel: WKInterfaceLabel!

    @IBOutlet weak var bolusButton: WKInterfaceGroup!

    @IBOutlet var decrementButton: WKInterfaceGroup!

    @IBOutlet var incremementButton: WKInterfaceGroup!

    @IBOutlet var bolusConfirmationInterfaceScene: WKInterfaceSKScene! {
        didSet {
            bolusConfirmationInterfaceScene.setHidden(true)
            bolusConfirmationInterfaceScene.setAlpha(0)
        }
    }

    // "Turn Digital Crown to bolus"
    @IBOutlet var bolusConfirmationHelpText: WKInterfaceLabel! {
        didSet {
            bolusConfirmationHelpText.setHidden(true)
            bolusConfirmationHelpText.setAlpha(0)
        }
    }

    private var bolusConfirmationScene: BolusConfirmationScene!

    private var willDeactivateObserver: AnyObject? {
        didSet {
            if let oldValue = oldValue {
                NotificationCenter.default.removeObserver(oldValue)
            }
        }
    }

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        let maxBolusValue: Double = ExtensionDelegate.shared().loopManager.settings.maximumBolus ?? 10
        var pickerValue = 0

        if let context = context as? WatchContext, let recommendedBolus = context.recommendedBolusDose {
            pickerValue = pickerValueFromBolusValue(recommendedBolus * ExtensionDelegate.shared().loopManager.settings.defaultWatchBolusPickerValue)

            if let valueString = formatter.string(from: recommendedBolus) {
                recommendedValueLabel.setText(String(format: NSLocalizedString("Rec: %@ U", comment: "The label and value showing the recommended bolus"), valueString).localizedUppercase)
            }
        }

        self.maxPickerValue = pickerValueFromBolusValue(maxBolusValue)
        self.pickerValue = pickerValue

        crownSequencer.delegate = self

        setupConfirmationScene()
    }

    override func didAppear() {
        super.didAppear()

        crownSequencer.focus()

        // If the screen turns off, the screen should be dismissed for safety reasons
        willDeactivateObserver = NotificationCenter.default.addObserver(forName: ExtensionDelegate.willResignActiveNotification, object: ExtensionDelegate.shared(), queue: nil, using: { [weak self] (_) in
            if let self = self {
                WKInterfaceDevice.current().play(.failure)
                self.dismiss()
            }
        })
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()

        willDeactivateObserver = nil
    }

    // MARK: - Value picking

    fileprivate var pickerValue: Int = 0 {
        didSet {
            guard pickerValue >= 0 else {
                pickerValue = 0
                return
            }

            guard pickerValue <= maxPickerValue else {
                pickerValue = maxPickerValue
                return
            }

            let bolusValue = bolusValueFromPickerValue(pickerValue)

            valueLabel.setLargeBoldRoundedText(formatter.string(fromBolusValue: bolusValue))
        }
    }

    private lazy var formatter: NumberFormatter = .bolus

    private var maxPickerValue = 0

    // MARK: - Confirmation

    private var resetTimer: Timer? {
        didSet {
            oldValue?.invalidate()
        }
    }

    fileprivate var accumulatedRotation: Double = 0
}

// MARK: - Bolus value

fileprivate let rotationsPerValue: Double = 1/24

private extension BolusInterfaceController {
    @IBAction func decrement() {
        guard case .picker = state else {
            return
        }

        pickerValue -= 10

        WKInterfaceDevice.current().play(.directionDown)
    }

    @IBAction func increment() {
        guard case .picker = state else {
            return
        }

        pickerValue += 10

        WKInterfaceDevice.current().play(.directionUp)
    }

    @IBAction func confirm() {
        guard case .picker = state else {
            return
        }

        let bolusValue = bolusValueFromPickerValue(pickerValue)

        if bolusValue > .ulpOfOne {
            state = .pickerFadeOut
        } else {
            willDeactivateObserver = nil
            dismiss()
        }
    }

    private func pickerValueFromBolusValue(_ bolusValue: Double) -> Int {
        switch bolusValue {
        case let bolus where bolus > 10:
            return Int((bolus - 10.0) * 10) + pickerValueFromBolusValue(10)
        case let bolus where bolus > 1:
            return Int((bolus - 1.0) * 20) + pickerValueFromBolusValue(1)
        default:
            return Int(bolusValue * 40)
        }
    }

    private func bolusValueFromPickerValue(_ pickerValue: Int) -> Double {
        switch pickerValue {
        case let picker where picker > 220:
            return Double(picker - 220) / 10.0 + bolusValueFromPickerValue(220)
        case let picker where picker > 40:
            return Double(picker - 40) / 20.0 + bolusValueFromPickerValue(40)
        default:
            return Double(pickerValue) / 40.0
        }
    }

    func updateBolusValueForAccumulatedRotation() {
        guard case .picker = state else {
            return
        }

        let remainder = accumulatedRotation.truncatingRemainder(dividingBy: rotationsPerValue)
        let delta = Int((accumulatedRotation - remainder) / rotationsPerValue)

        pickerValue += delta

        accumulatedRotation = remainder
    }
}

extension BolusInterfaceController {
    private func setupConfirmationScene() {
        var config = BolusConfirmationScene.Configuration()
        config.arrow.tintColor = .insulin
        config.backgroundColor = .darkInsulin

        bolusConfirmationScene = BolusConfirmationScene(configuration: config)
        bolusConfirmationInterfaceScene.presentScene(bolusConfirmationScene)
    }

    func deliver() {
        willDeactivateObserver = nil

        let bolusValue = bolusValueFromPickerValue(pickerValue)
        let bolus = SetBolusUserInfo(value: bolusValue, startDate: Date())

        if bolus.value > .ulpOfOne {
            do {
                try WCSession.default.sendBolusMessage(bolus) { (error) in
                    DispatchQueue.main.async {
                        if let error = error {
                            ExtensionDelegate.shared().present(error)
                        } else {
                            ExtensionDelegate.shared().loopManager.addConfirmedBolus(bolus)
                        }
                    }
                }
            } catch {
                presentAlert(
                    withTitle: NSLocalizedString("Bolus Failed", comment: "The title of the alert controller displayed after a bolus attempt fails"),
                    message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a bolus attempt fails"),
                    preferredStyle: .alert,
                    actions: [WKAlertAction.dismissAction()]
                )
                return
            }
        }

        dismiss()
    }

    func updateBolusConfirmationForAccumulatedRotation(previousAccumulatedRotation: Double) {
        resetTimer = nil
        bolusConfirmationScene.setProgress(CGFloat(abs(accumulatedRotation)))

        // Indicate to the user that they've hit the threshold
        if abs(previousAccumulatedRotation) < 1.0 && abs(accumulatedRotation) >= 1.0 {
            WKInterfaceDevice.current().play(.success)
        }
    }

    func completeBolusConfirmation() {
        crownSequencer.delegate = nil
        bolusConfirmationScene.setFinished()
        animate(withDuration: 0.25) {
            self.bolusConfirmationHelpText.setAlpha(0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
            self.deliver()
        }
    }

    func scheduleBolusConfirmationReset() {
        resetTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false, block: { [weak self] (timer) in
            if timer.isValid, let self = self {
                self.accumulatedRotation = 0
                self.bolusConfirmationScene.setProgress(0, animationDuration: 0.25)
            }
        })
    }
}

// MARK: - WKCrownDelegate
extension BolusInterfaceController: WKCrownDelegate {
    func crownDidRotate(_ crownSequencer: WKCrownSequencer?, rotationalDelta: Double) {
        let previousAccumulatedRotation = accumulatedRotation
        accumulatedRotation += rotationalDelta

        switch state {
        case .picker:
            updateBolusValueForAccumulatedRotation()
        case .pickerFadeOut, .confirmFadeIn:
            break
        case .confirm:
            updateBolusConfirmationForAccumulatedRotation(previousAccumulatedRotation: previousAccumulatedRotation)
        }
    }

    func crownDidBecomeIdle(_ crownSequencer: WKCrownSequencer?) {
        guard case .confirm = state else {
            return
        }

        // If we've completed a full rotation, animate and dismiss
        if abs(accumulatedRotation) >= 1 {
            completeBolusConfirmation()
        } else {
            scheduleBolusConfirmationReset()
        }
    }
}
