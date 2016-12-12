//
//  StatusViewController.swift
//  Loop Status Extension
//
//  Created by Bharat Mediratta on 11/25/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit
import NotificationCenter
import HealthKit
import CoreData

class StatusViewController: UIViewController, NCWidgetProviding {
    
    @IBOutlet weak var loopCompletionHUD: LoopCompletionHUDView!
    @IBOutlet weak var glucoseHUD: GlucoseHUDView!
    @IBOutlet weak var basalRateHUD: BasalRateHUDView!
    @IBOutlet weak var reservoirVolumeHUD: ReservoirVolumeHUDView!
    @IBOutlet weak var batteryHUD: BatteryLevelHUDView!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        subtitleLabel.alpha = 0
        subtitleLabel.textColor = UIColor.secondaryLabelColor
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        guard
            let context = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)?.statusExtensionContext
        else {
            completionHandler(NCUpdateResult.failed)
            return
        }

        // We should never have the case where there's glucose values but no preferred
        // unit. However, if that case were to happen we might show quantities against
        // the wrong units and that could be very harmful. So unless there's a preferred
        // unit, assume that none of the rest of the data is reliable.
        guard
            let preferredUnitString = context.preferredUnitString
        else {
            completionHandler(NCUpdateResult.failed)
            return
        }
        
        if let glucose = context.latestGlucose {
            glucoseHUD.set(glucoseQuantity: glucose.quantity,
                           at: glucose.startDate,
                           unitString: preferredUnitString,
                           from: glucose.sensor)
        }
        
        if let batteryPercentage = context.batteryPercentage {
            batteryHUD.batteryLevel = Double(batteryPercentage)
        }
        
        if let reservoir = context.reservoir {
            reservoirVolumeHUD.reservoirLevel = min(1, max(0, Double(reservoir.unitVolume / Double(reservoir.capacity))))
            reservoirVolumeHUD.setReservoirVolume(volume: reservoir.unitVolume, at: reservoir.startDate)
        }

        if let netBasal = context.netBasal {
            basalRateHUD.setNetBasalRate(netBasal.rate, percent: netBasal.percentage, at: netBasal.startDate)
        }

        if let loop = context.loop {
            loopCompletionHUD.dosingEnabled = loop.dosingEnabled
            loopCompletionHUD.lastLoopCompleted = loop.lastCompleted
        }

        let preferredUnit = HKUnit(from: preferredUnitString)
        let formatter = NumberFormatter.glucoseFormatter(for: preferredUnit)
        if let eventualGlucose = context.eventualGlucose,
           let eventualGlucoseNumberString = formatter.string(from: NSNumber(value: eventualGlucose)) {
            subtitleLabel.text = String(
                    format: NSLocalizedString(
                        "Eventually %1$@ %2$@",
                        comment: "The subtitle format describing eventual glucose. (1: localized glucose value description) (2: localized glucose units description)"),
                    eventualGlucoseNumberString,
                    preferredUnit.glucoseUnitDisplayString)
            subtitleLabel.alpha = 1
        } else {
            subtitleLabel.alpha = 0
        }

        // Right now we always act as if there's new data.
        // TODO: keep track of data changes and return .noData if necessary
        completionHandler(NCUpdateResult.newData)
    }
    
}
