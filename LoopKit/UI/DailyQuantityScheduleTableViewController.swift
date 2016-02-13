//
//  DailyQuantityScheduleTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/13/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit


public class DailyQuantityScheduleTableViewController: DailyValueScheduleTableViewController {

    public var unit: HKUnit = HKUnit.gramUnit() {
        didSet {
            unitString = "\(unit)/U"
        }
    }

}
