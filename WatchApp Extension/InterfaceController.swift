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


class InterfaceController: WKInterfaceController, WCSessionDelegate {

    @IBOutlet var glucoseLabel: WKInterfaceLabel!
    @IBOutlet var glucoseUnitLabel: WKInterfaceLabel!

    @IBOutlet var IOBLabel: WKInterfaceLabel!
    @IBOutlet var reservoirLabel: WKInterfaceLabel!

    private var connectSession: WCSession?

    private var lastStatusUpdateTime: NSDate?

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)
        
        if WCSession.isSupported() {
            connectSession = WCSession.defaultSession()
            connectSession?.delegate = self
            connectSession?.activateSession()
        }
    }

    override func willActivate() {
        super.willActivate()

        if lastStatusUpdateTime != nil && NSDate().timeIntervalSinceDate(lastStatusUpdateTime!) > 15.minutes {
            lastStatusUpdateTime = nil
            clearAllLabels()
        }
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

    private func clearAllLabels() {
        glucoseLabel.setText("--")
        glucoseUnitLabel.setHidden(false)
        IOBLabel.setText("-.-")
        reservoirLabel.setText("-.-")
    }

    // MARK: - WCSessionDelegate

    func session(session: WCSession, didReceiveApplicationContext applicationContext: [String : AnyObject]) {
        if let statusData = applicationContext["statusData"] as? NSData, status = MySentryPumpStatusMessageBody(rxData: statusData) {

            dispatch_async(dispatch_get_main_queue()) { [weak self = self] () -> Void in
                self?.lastStatusUpdateTime = status.pumpDate

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
        }
    }
}
