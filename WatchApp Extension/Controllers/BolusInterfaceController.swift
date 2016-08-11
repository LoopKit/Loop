//
//  BolusInterfaceController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import Foundation


final class BolusInterfaceController: WKInterfaceController, IdentifiableClass {

    private var bolusValue: Double = 0 {
        didSet {
            switch bolusValue {
            case let x where x < 1:
                formatter.minimumFractionDigits = 3
            case let x where x < 10:
                formatter.minimumFractionDigits = 2
            default:
                formatter.minimumFractionDigits = 1
            }

            valueLabel.setText(formatter.stringFromNumber(bolusValue) ?? "--")
        }
    }

    private var maxBolusValue: Double = 15

    private func pickerValueFromBolusValue(bolusValue: Double) -> Int {
        switch bolusValue {
        case let bolus where bolus > 10:
            return Int((bolus - 10.0) * 10) + pickerValueFromBolusValue(10)
        case let bolus where bolus > 1:
            return Int((bolus - 1.0) * 20) + pickerValueFromBolusValue(1)
        default:
            return Int(bolusValue * 40)
        }
    }

    private func bolusValueFromPickerValue(pickerValue: Int) -> Double {
        switch pickerValue {
        case let picker where picker > 220:
            return Double(picker - 220) / 10.0 + bolusValueFromPickerValue(220)
        case let picker where picker > 40:
            return Double(picker - 40) / 20.0 + bolusValueFromPickerValue(40)
        default:
            return Double(pickerValue) / 40.0
        }
    }

    private lazy var formatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .DecimalStyle
        formatter.minimumIntegerDigits = 1

        return formatter
    }()

    /// 1.25
    @IBOutlet var valueLabel: WKInterfaceLabel!

    @IBOutlet var valuePicker: WKInterfacePicker!

    /// REC: 2.25 U
    @IBOutlet var recommendedValueLabel: WKInterfaceLabel!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        let maxPickerValue: Int
        let pickerValue: Int

        if let context = context as? BolusSuggestionUserInfo {
            maxPickerValue = pickerValueFromBolusValue(context.recommendedBolus)
            maxBolusValue = bolusValueFromPickerValue(maxPickerValue)
            pickerValue = Int(Double(maxPickerValue) * 0.75)
            bolusValue = bolusValueFromPickerValue(pickerValue)

            if let valueString = formatter.stringFromNumber(maxBolusValue) {
                recommendedValueLabel.setText(String(format: NSLocalizedString("Rec: %@ U", comment: "The label and value showing the recommended bolus"), valueString).localizedUppercaseString)
            }
        } else {
            maxPickerValue = pickerValueFromBolusValue(maxBolusValue)
            pickerValue = pickerValueFromBolusValue(bolusValue)
            bolusValue = 0
        }

        let items = (0...maxPickerValue).map { _ in WKPickerItem() }
        valuePicker.setItems(items)
        valuePicker.setSelectedItemIndex(pickerValue)
    }

    override func willActivate() {
        // This method is called when watch view controller is about to be visible to user
        super.willActivate()

        valuePicker.focus()
    }

    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }

    // MARK: - Actions

    @IBAction func pickerValueUpdated(value: Int) {
        bolusValue = bolusValueFromPickerValue(value)
    }

    @IBAction func decrement() {
        valuePicker.setSelectedItemIndex(pickerValueFromBolusValue(bolusValue) - 10)
    }

    @IBAction func increment() {
        valuePicker.setSelectedItemIndex(pickerValueFromBolusValue(bolusValue) + 10)
    }

    @IBAction func deliver() {
        if bolusValue > 0 {
            let bolus = SetBolusUserInfo(value: bolusValue, startDate: NSDate())
            do {
                try DeviceDataManager.sharedManager.sendSetBolus(bolus)
            } catch DeviceDataManager.Error.ReachabilityError {
                presentAlertControllerWithTitle(NSLocalizedString("Bolus Failed", comment: "The title of the alert controller displayed after a bolus attempt fails"),
                    message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a bolus attempt fails"),
                    preferredStyle: .Alert,
                    actions: [WKAlertAction.dismissAction()]
                )
                return
            } catch {
            }
        }

        dismissController()
    }

}
