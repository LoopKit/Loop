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

    private var absorptionTime = AbsorptionTimeType.medium {
        didSet {
            absorptionButtonA.setBackgroundColor(UIColor.darkTintColor)
            absorptionButtonB.setBackgroundColor(UIColor.darkTintColor)
            absorptionButtonC.setBackgroundColor(UIColor.darkTintColor)

            switch absorptionTime {
            case .fast:
                absorptionButtonA.setBackgroundColor(UIColor.tintColor)
            case .medium:
                absorptionButtonB.setBackgroundColor(UIColor.tintColor)
            case .slow:
                absorptionButtonC.setBackgroundColor(UIColor.tintColor)
            }
        }
    }

    @IBOutlet var valueLabel: WKInterfaceLabel!

    @IBOutlet var valuePicker: WKInterfacePicker!

    @IBOutlet var absorptionButtonA: WKInterfaceButton!

    @IBOutlet var absorptionButtonB: WKInterfaceButton!

    @IBOutlet var absorptionButtonC: WKInterfaceButton!

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.

        let items = (0...100).map { _ in WKPickerItem() }

        valuePicker.setItems(items)

        valuePicker.setSelectedItemIndex(carbValue)

        absorptionTime = .medium
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

    @IBAction func pickerValueUpdated(_ value: Int) {
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
        absorptionTime = .fast
    }

    @IBAction func setAbsorptionTimeMedium() {
        absorptionTime = .medium
    }

    @IBAction func setAbsorptionTimeSlow() {
        absorptionTime = .slow
    }

    @IBAction func save() {
        if carbValue > 0 {
            let entry = CarbEntryUserInfo(value: Double(carbValue), absorptionTimeType: absorptionTime, startDate: Date())

            DeviceDataManager.sharedManager.sendCarbEntry(entry)
        }

        dismiss()
    }

}
