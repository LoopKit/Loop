//
//  StatusInterfaceController.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import Foundation


final class StatusInterfaceController: WKInterfaceController, ContextUpdatable {

    @IBOutlet weak var graphImage: WKInterfaceImage!
    @IBOutlet weak var loopHUDImage: WKInterfaceImage!
    @IBOutlet weak var loopTimer: WKInterfaceTimer!
    @IBOutlet weak var glucoseLabel: WKInterfaceLabel!
    @IBOutlet weak var eventualGlucoseLabel: WKInterfaceLabel!
    @IBOutlet weak var statusLabel: WKInterfaceLabel!

    private var lastContext: WatchContext?

    func update(with context: WatchContext?) {
        lastContext = context

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
        } else {
            loopTimer.setHidden(true)
            loopHUDImage.setLoopImage(.Unknown)
        }

        let numberFormatter = NumberFormatter()

        if let glucose = context?.glucose, let unit = context?.preferredGlucoseUnit {
            let glucoseValue = glucose.doubleValue(for: unit)
            let trend = context?.glucoseTrend?.symbol ?? ""

            self.glucoseLabel.setText((numberFormatter.string(from: NSNumber(value: glucoseValue)) ?? "") + trend)
            self.glucoseLabel.setHidden(false)
        } else {
            glucoseLabel.setHidden(true)
        }

        if let eventualGlucose = context?.eventualGlucose, let unit = context?.preferredGlucoseUnit {
            let glucoseValue = eventualGlucose.doubleValue(for: unit)

            self.eventualGlucoseLabel.setText(numberFormatter.string(from: NSNumber(value: glucoseValue)))
            self.eventualGlucoseLabel.setHidden(false)
        } else {
            eventualGlucoseLabel.setHidden(true)
        }

        // TODO: Other elements
        statusLabel.setHidden(true)
        graphImage.setHidden(true)
    }

    // MARK: - Menu Items

    @IBAction func addCarbs() {
        presentController(withName: AddCarbsInterfaceController.className, context: nil)
    }

    @IBAction func setBolus() {
        presentController(withName: BolusInterfaceController.className, context: lastContext?.bolusSuggestion)
    }

}
