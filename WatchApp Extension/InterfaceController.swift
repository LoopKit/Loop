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

        dataManager.addObserver(self, forKeyPath: "lastStatusData", options: [], context: &lastStatusDataObserverContext)

        lastStatusUpdate = MySentryPumpStatusMessageBody(rxData: dataManager.lastStatusData ?? NSData())
    }

    override func didDeactivate() {
        dataManager.removeObserver(self, forKeyPath: "lastStatusData", context: &lastStatusDataObserverContext)

        super.didDeactivate()
    }

    // MARK: - Data

    private var lastStatusDataObserverContext = 0

    private func clearAllLabels() {
        glucoseLabel.setText("--")
        glucoseUnitLabel.setHidden(false)
        IOBLabel.setText("-.-")
        reservoirLabel.setText("-.-")
    }

    private var lastStatusUpdate: MySentryPumpStatusMessageBody? {
        didSet {
            dispatch_async(dispatch_get_main_queue()) { [weak self = self, oldValue = oldValue] () -> Void in
                if let status = self?.lastStatusUpdate where NSDate().timeIntervalSinceDate(status.pumpDate) <= 15.minutes {
                    if oldValue != status {
                        switch status.glucose {
                        case .Active(glucose: let glucose):
                            let direction: String

                            switch status.glucoseTrend {
                            case .Flat:
                                direction = ""
                            case .Down:
                                direction = "↓ "
                            case .DownDown:
                                direction = "⇊ "
                            case .Up:
                                direction = "↑ "
                            case .UpUp:
                                direction = "⇈ "
                            }

                            self?.glucoseLabel.setText("\(direction)\(glucose)")
                            self?.glucoseUnitLabel.setHidden(false)
                        default:
                            self?.glucoseLabel.setText(String(status.glucose))
                            self?.glucoseUnitLabel.setHidden(true)
                        }

                        let decimalFormatter = NSNumberFormatter()
                        decimalFormatter.numberStyle = .DecimalStyle

                        self?.IOBLabel.setText(decimalFormatter.stringFromNumber(status.iob))
                        self?.reservoirLabel.setText(decimalFormatter.stringFromNumber(status.reservoirRemainingUnits))
                    }
                } else {
                    self?.clearAllLabels()
                }
            }
        }
    }

    // MARK: - KVO

    override func observeValueForKeyPath(keyPath: String?, ofObject object: AnyObject?, change: [String : AnyObject]?, context: UnsafeMutablePointer<Void>) {
        if context == &lastStatusDataObserverContext {
            if let data = dataManager.lastStatusData {
                lastStatusUpdate = MySentryPumpStatusMessageBody(rxData: data)
            }
        } else {
            super.observeValueForKeyPath(keyPath, ofObject: object, change: change, context: context)
        }
    }
}
