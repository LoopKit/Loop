//
//  InterfaceController.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import ClockKit
import WatchKit
import Foundation
import WatchConnectivity


class InterfaceController: ContextInterfaceController {

    @IBOutlet var glucoseLabel: WKInterfaceLabel!
    @IBOutlet var glucoseUnitLabel: WKInterfaceLabel!
    @IBOutlet var glucoseDateLabel: WKInterfaceLabel!
    @IBOutlet var pumpDateLabel: WKInterfaceLabel?
    @IBOutlet var IOBLabel: WKInterfaceLabel!
    @IBOutlet var reservoirLabel: WKInterfaceLabel!

    lazy var dateFormatter: NSDateComponentsFormatter = {
        let dateFormatter = NSDateComponentsFormatter()
        dateFormatter.unitsStyle = .Abbreviated
        dateFormatter.allowedUnits = [.Hour, .Minute]

        return dateFormatter
    }()

    lazy var numberFormatter = NSNumberFormatter()

    // MARK: - Data

    override func updateFromContext(context: WatchContext?) {
        super.updateFromContext(context)

        dispatch_async(dispatch_get_main_queue()) {
            if let iob = context?.IOB, reservoir = context?.reservoir
            {
                let decimalFormatter = NSNumberFormatter()
                decimalFormatter.numberStyle = .DecimalStyle

                self.IOBLabel.setText(decimalFormatter.stringFromNumber(iob))
                self.reservoirLabel.setText(decimalFormatter.stringFromNumber(reservoir))
            } else {
                self.IOBLabel.setText("-.-")
                self.reservoirLabel.setText("-.-")
            }

            if let date = context?.glucoseDate where NSDate().timeIntervalSinceDate(date).minutes <= 60,
                let context = context, glucose = context.glucose
            {
                if let dateString = self.dateFormatter.stringFromDate(date, toDate: NSDate()) {
                    self.glucoseDateLabel.setText("\(dateString) ago")
                }

                guard let unit = context.preferredGlucoseUnit else {
                    return
                }

                let glucoseValue = glucose.doubleValueForUnit(unit)

                self.glucoseLabel.setText(
                    context.glucoseTrendDescription +
                    (self.numberFormatter.stringFromNumber(glucoseValue) ?? "")
                )
            } else {
                self.glucoseLabel.setText("--")
                self.glucoseUnitLabel.setHidden(false)
            }
        }
    }

    // MARK: - Menu Items

    @IBAction func addCarbs() {
        presentControllerWithName(AddCarbsInterfaceController.className, context: nil)
    }

    @IBAction func setBolus() {
        presentControllerWithName(BolusInterfaceController.className, context: nil)
    }
}
