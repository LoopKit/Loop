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
    
    @IBOutlet weak var glucoseHUD: GlucoseHUDView!
        
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
            glucoseHUD.set(context.latestGlucose, for: HKUnit.milligramsPerDeciliterUnit(), from: nil)
        }

        completionHandler(NCUpdateResult.newData)
    }
    
}
