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

    override func updateFromContext(_ context: WatchContext?) {
        super.updateFromContext(context)

        resetInterface()

        DispatchQueue.main.async {
            if let date = context?.loopLastRunDate {
                self.loopTimer.setDate(date as Date)
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

        let numberFormatter = NumberFormatter()

        DispatchQueue.main.async {
            if let glucose = context?.glucose, let unit = context?.preferredGlucoseUnit {
                let glucoseValue = glucose.doubleValue(for: unit)
                let trend = context?.glucoseTrend?.description ?? ""

                self.glucoseLabel.setText((numberFormatter.string(from: NSNumber(value: glucoseValue)) ?? "") + trend)
                self.glucoseLabel.setHidden(false)
            }

            if let eventualGlucose = context?.eventualGlucose, let unit = context?.preferredGlucoseUnit {
                let glucoseValue = eventualGlucose.doubleValue(for: unit)

                self.eventualGlucoseLabel.setText(numberFormatter.string(from: NSNumber(value: glucoseValue)))
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
        presentController(withName: AddCarbsInterfaceController.className, context: nil)
    }

    @IBAction func setBolus() {
        presentController(withName: BolusInterfaceController.className, context: dataManager.lastContextData?.bolusSuggestion)
    }

}
