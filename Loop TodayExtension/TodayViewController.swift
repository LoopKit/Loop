//
//  TodayViewController.swift
//  Loop TodayExtension
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

class TodayViewController: UIViewController, NCWidgetProviding {
    
    @IBOutlet weak var loopCompletionHUD: LoopCompletionHUDView!
    @IBOutlet weak var glucoseHUD: GlucoseHUDView!
    @IBOutlet weak var basalRateHUD: BasalRateHUDView!
    @IBOutlet weak var reservoirVolumeHUD: ReservoirVolumeHUDView!
    @IBOutlet weak var batteryHUD: BatteryLevelHUDView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view from its nib.
        
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func widgetPerformUpdate(completionHandler: (@escaping (NCUpdateResult) -> Void)) {
        // Perform any setup necessary in order to update the view.
        
        // If an error is encountered, use NCUpdateResult.Failed
        // If there's no update required, use NCUpdateResult.NoData
        // If there's an update, use NCUpdateResult.NewData
        
        if let context = TodayExtensionContext().load() {
            if context.hasLatestGlucose {
                glucoseHUD.set(context.latestGlucose, for: HKUnit.milligramsPerDeciliterUnit(), from: nil)
            }
            
            if context.hasBattery {
                batteryHUD.batteryLevel = Double(context.batteryPercentage)
            }
                
            if context.hasReservoir {
                reservoirVolumeHUD.reservoirLevel = min(1, max(0, Double(context.reservoir.unitVolume / Double(context.reservoirCapacity))))
                reservoirVolumeHUD.setReservoirVolume(volume: context.reservoir.unitVolume, at: context.reservoir.startDate)
            }

            if context.hasBasal {
                basalRateHUD.setNetBasalRate(context.netBasalRate, percent: context.netBasalPercent, at: context.basalStartDate)
            }
            
            loopCompletionHUD.dosingEnabled = false
            loopCompletionHUD.dosingEnabled = context.dosingEnabled
            
            completionHandler(NCUpdateResult.newData)
        }
        
    }
    
}
