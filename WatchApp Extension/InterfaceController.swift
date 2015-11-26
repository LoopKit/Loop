//
//  InterfaceController.swift
//  WatchApp Extension
//
//  Created by Nathan Racklyeft on 8/29/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import Foundation
import WatchConnectivity


extension Int {
    var minutes: NSTimeInterval {
        return NSTimeInterval(self * 60)
    }
}


class InterfaceController: WKInterfaceController {

    @IBOutlet var glucoseLabel: WKInterfaceLabel!
    @IBOutlet var glucoseUnitLabel: WKInterfaceLabel!

    @IBOutlet var IOBLabel: WKInterfaceLabel!
    @IBOutlet var reservoirLabel: WKInterfaceLabel!

    let dataManager = PumpDataManager.sharedManager

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
    }

    override func willActivate() {
        super.willActivate()

        dataManager.addObserver(self, forKeyPath: "lastContextData", options: [], context: &lastContextDataObserverContext)

        updateFromContext(dataManager.lastContextData)
    }

    override func didDeactivate() {
        dataManager.removeObserver(self, forKeyPath: "lastContextData", context: &lastContextDataObserverContext)

        super.didDeactivate()
    }

    // MARK: - Data

    private var lastContextDataObserverContext = 0

    private func updateFromContext(context: WatchContext?) {
        dispatch_async(dispatch_get_main_queue()) { [weak self] in
            if let date = context?.pumpDate where NSDate().timeIntervalSinceDate(date) <= 15.minutes,
                let iob = context?.IOB, reservoir = context?.reservoir
            {
                let decimalFormatter = NSNumberFormatter()
                decimalFormatter.numberStyle = .DecimalStyle

                self?.IOBLabel.setText(decimalFormatter.stringFromNumber(iob))
                self?.reservoirLabel.setText(decimalFormatter.stringFromNumber(reservoir))
            } else {
                self?.IOBLabel.setText("-.-")
                self?.reservoirLabel.setText("-.-")
            }

            if let date = context?.glucoseDate where NSDate().timeIntervalSinceDate(date) <= 15.minutes,
                let glucose = context?.glucoseValue, trend = context?.glucoseTrend
            {
                let direction: String
                switch trend {
                case let x where x < -10:
                    direction = "⇊"
                case let x where x < 0:
                    direction = "↓"
                case let x where x > 10:
                    direction = "⇈"
                case let x where x > 0:
                    direction = "↑"
                default:
                    direction = ""
                }

                self?.glucoseLabel.setText("\(direction)\(glucose)")
            } else {
                self?.glucoseLabel.setText("--")
                self?.glucoseUnitLabel.setHidden(false)
            }
        }
    }

    // MARK: - KVO

    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context == &lastContextDataObserverContext {
            if let context = dataManager.lastContextData {
                updateFromContext(context)
            }
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
}
