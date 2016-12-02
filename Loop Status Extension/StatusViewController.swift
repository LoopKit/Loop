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
        guard let context = UserDefaults.shared()?.statusExtensionContext else {
            completionHandler(NCUpdateResult.failed)
            return
        }

        // It's possible that Loop couldn't pull the preferred unit for some reason so
        // we might have a nil value here. Fall back on mg/DL for now in that case.
        // This should go away with https://github.com/LoopKit/LoopKit/issues/27
        let preferredUnit = context.preferredUnit ?? HKUnit.milligramsPerDeciliterUnit()
        
        if let glucose = context.latestGlucose {
            glucoseHUD.set(glucose.latest, for: preferredUnit, from: glucose.sensor)
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

        if let eventualGlucose = context.eventualGlucose {
            let quantity = HKQuantity(unit: preferredUnit,
                                      doubleValue: eventualGlucose.rounded())
            subtitleLabel.text = String(
                    format: NSLocalizedString(
                        "Eventually %@",
                        comment: "The subtitle format describing eventual glucose. (1: localized glucose value description)"),
                    String(describing: quantity))
            subtitleLabel.alpha = 1
        } else {
            subtitleLabel.alpha = 0
        }

        // Right now we always act as if there's new data.
        // TODO: keep track of data changes and return .noData if necessary
        completionHandler(NCUpdateResult.newData)
    }
    
}
