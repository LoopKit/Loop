//
//  AddCarbsInterfaceController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import WatchConnectivity


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

            do {
                try WCSession.default().sendCarbEntryMessage(entry,
                    replyHandler: { (suggestion) in
                        WKExtension.shared().rootInterfaceController?.presentController(withName: BolusInterfaceController.className, context: suggestion)
                    },
                    errorHandler: { (error) in
                        ExtensionDelegate.shared().present(error)
                    }
                )
            } catch {
                presentAlert(withTitle: NSLocalizedString("Send Failed", comment: "The title of the alert controller displayed after a carb entry send attempt fails"),
                    message: NSLocalizedString("Make sure your iPhone is nearby and try again", comment: "The recovery message displayed after a carb entry send attempt fails"),
                    preferredStyle: .alert,
                    actions: [WKAlertAction.dismissAction()]
                )
                return
            }
        }

        dismiss()
    }

}
