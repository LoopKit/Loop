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
import GlucoseKit
import LoopKit
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
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        if let context = UserDefaults.shared()?.statusExtensionContext {
            if let glucose = context.latestGlucose {
                glucoseHUD.set(glucose.latest, for: HKUnit.milligramsPerDeciliterUnit(), from: glucose.sensor)
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
                subtitleLabel.text = eventualGlucose
                subtitleLabel.textColor = UIColor.secondaryLabelColor
                subtitleLabel.alpha = 1
            } else {
                subtitleLabel.alpha = 0
            }

            // Right now we always act as if there's new data.
            // TODO: keep track of data changes and return .noData if necessary
            completionHandler(NCUpdateResult.newData)
        } else {
            completionHandler(NCUpdateResult.failed)
        }

    }
    
}
