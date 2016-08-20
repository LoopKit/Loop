//
//  AddCarbsInterfaceController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import Foundation


final class AddCarbsInterfaceController: WKInterfaceController, IdentifiableClass {

    private var carbValue: Int = 15

    private var absorptionTime = AbsorptionTimeType.Medium {
        didSet {
            absorptionButtonA.setBackgroundColor(UIColor.darkTintColor)
            absorptionButtonB.setBackgroundColor(UIColor.darkTintColor)
            absorptionButtonC.setBackgroundColor(UIColor.darkTintColor)

            switch absorptionTime {
            case .Fast:
                absorptionButtonA.setBackgroundColor(UIColor.tintColor)
            case .Medium:
                absorptionButtonB.setBackgroundColor(UIColor.tintColor)
            case .Slow:
                absorptionButtonC.setBackgroundColor(UIColor.tintColor)
            }
        }
    }

    @IBOutlet var valueLabel: WKInterfaceLabel!

    @IBOutlet var valuePicker: WKInterfacePicker!

    @IBOutlet var absorptionButtonA: WKInterfaceButton!

    @IBOutlet var absorptionButtonB: WKInterfaceButton!

    @IBOutlet var absorptionButtonC: WKInterfaceButton!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
        // Configure interface objects here.

        let items = (0...100).map { _ in WKPickerItem() }

        valuePicker.setItems(items)

        valuePicker.setSelectedItemIndex(carbValue)

        absorptionTime = .Medium
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
        carbValue = value
        valueLabel.setText(String(value))
    }

    @IBAction func decrement() {
        valuePicker.setSelectedItemIndex(carbValue - 5)
    }

    @IBAction func increment() {
        valuePicker.setSelectedItemIndex(carbValue + 5)
    }

    @IBAction func setAbsorptionTimeFast() {
        absorptionTime = .Fast
    }

    @IBAction func setAbsorptionTimeMedium() {
        absorptionTime = .Medium
    }

    @IBAction func setAbsorptionTimeSlow() {
        absorptionTime = .Slow
    }

    @IBAction func save() {
        if carbValue > 0 {
            let entry = CarbEntryUserInfo(value: Double(carbValue), absorptionTimeType: absorptionTime, startDate: NSDate())

            DeviceDataManager.sharedManager.sendCarbEntry(entry)
        }

        dismissController()
    }

}
