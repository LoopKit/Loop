//
//  StatusInterfaceController.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import Foundation


final class StatusInterfaceController: ContextInterfaceController {

    @IBOutlet var graphImage: WKInterfaceImage!
    @IBOutlet var loopHUDImage: WKInterfaceImage!
    @IBOutlet var loopTimer: WKInterfaceTimer!
    @IBOutlet var glucoseLabel: WKInterfaceLabel!
    @IBOutlet var eventualGlucoseLabel: WKInterfaceLabel!
    @IBOutlet var statusLabel: WKInterfaceLabel!

    override func updateFromContext(context: WatchContext?) {
        super.updateFromContext(context)

        resetInterface()

        dispatch_async(dispatch_get_main_queue()) {
            if let date = context?.loopLastRunDate {
                self.loopTimer.setDate(date)
                self.loopTimer.setHidden(false)
                self.loopTimer.start()

                let loopImage: LoopImage

                switch date.timeIntervalSinceNow {
                case let t where t.minutes <= 5:
                    loopImage = .Fresh
                case let t where t.minutes <= 15:
                    loopImage = .Aging
                default:
                    loopImage = .Stale
                }

                self.loopHUDImage.setLoopImage(loopImage)
            }
        }

        let numberFormatter = NSNumberFormatter()

        dispatch_async(dispatch_get_main_queue()) {
            if let glucose = context?.glucose, unit = context?.preferredGlucoseUnit {
                let glucoseValue = glucose.doubleValueForUnit(unit)
                let trend = context?.glucoseTrend?.description ?? ""

                self.glucoseLabel.setText((numberFormatter.stringFromNumber(glucoseValue) ?? "") + trend)
                self.glucoseLabel.setHidden(false)
            }

            if let eventualGlucose = context?.eventualGlucose, unit = context?.preferredGlucoseUnit {
                let glucoseValue = eventualGlucose.doubleValueForUnit(unit)

                self.eventualGlucoseLabel.setText(numberFormatter.stringFromNumber(glucoseValue))
                self.eventualGlucoseLabel.setHidden(false)
            }
        }
    }

    private func resetInterface() {
        loopTimer.setHidden(true)
        statusLabel.setHidden(true)
        graphImage.setHidden(true)
        glucoseLabel.setHidden(true)
        eventualGlucoseLabel.setHidden(true)
        loopHUDImage.setLoopImage(.Unknown)
    }

    // MARK: - Menu Items

    @IBAction func addCarbs() {
        presentControllerWithName(AddCarbsInterfaceController.className, context: nil)
    }

    @IBAction func setBolus() {
        presentControllerWithName(BolusInterfaceController.className, context: nil)
    }

}
