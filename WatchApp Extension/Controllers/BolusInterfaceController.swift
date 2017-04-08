//
//  BolusInterfaceController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import Foundation
import WatchConnectivity


final class BolusInterfaceController: WKInterfaceController, IdentifiableClass {

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

            switch bolusValue {
            case let x where x < 1:
                formatter.minimumFractionDigits = 3
            case let x where x < 10:
                formatter.minimumFractionDigits = 2
            default:
                formatter.minimumFractionDigits = 1
            }

            valueLabel.setText(formatter.string(from: NSNumber(value: bolusValue)) ?? "--")
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

    private lazy var formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 1

        return formatter
    }()

    private var maxPickerValue = 0

    /// 1.25
    @IBOutlet weak var valueLabel: WKInterfaceLabel!

    /// REC: 2.25 U
    @IBOutlet weak var recommendedValueLabel: WKInterfaceLabel!

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)

        var maxBolusValue: Double = 15
        var pickerValue = 0

        if let context = context as? BolusSuggestionUserInfo {
            let recommendedBolus = context.recommendedBolus

            if let maxBolus = context.maxBolus {
                maxBolusValue = maxBolus
            } else if recommendedBolus > 0 {
                maxBolusValue = recommendedBolus
            }

            let recommendedPickerValue = pickerValueFromBolusValue(recommendedBolus)
            pickerValue = Int(Double(recommendedPickerValue) * 1)

            if let valueString = formatter.string(from: NSNumber(value: recommendedBolus)) {
                recommendedValueLabel.setText(String(format: NSLocalizedString("Rec: %@ U", comment: "The label and value showing the recommended bolus"), valueString).localizedUppercase)
            }
        }

        self.maxPickerValue = pickerValueFromBolusValue(maxBolusValue)
        self.pickerValue = pickerValue

        crownSequencer.delegate = self
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()

        crownSequencer.focus()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    // MARK: - Actions

    @IBAction func decrement() {
        pickerValue -= 10
    }

    @IBAction func increment() {
        pickerValue += 10
    }

    @IBAction func deliver() {
        let bolusValue = bolusValueFromPickerValue(pickerValue)

        if bolusValue > 0 {
            let bolus = SetBolusUserInfo(value: bolusValue, startDate: Date())

            do {
                try WCSession.default().sendBolusMessage(bolus) { (error) in
                    ExtensionDelegate.shared().present(error)
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

    // MARK: - Crown Sequencer

    fileprivate var accumulatedRotation: Double = 0
}

fileprivate let rotationsPerValue: Double = 1/24

extension BolusInterfaceController: WKCrownDelegate {
    func crownDidRotate(_ crownSequencer: WKCrownSequencer?, rotationalDelta: Double) {
        accumulatedRotation += rotationalDelta

        let remainder = accumulatedRotation.truncatingRemainder(dividingBy: rotationsPerValue)
        pickerValue += Int((accumulatedRotation - remainder).divided(by: rotationsPerValue))
        accumulatedRotation = remainder
    }
}
