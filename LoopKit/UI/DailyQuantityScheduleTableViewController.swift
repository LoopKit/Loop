//
//  DailyQuantityScheduleTableViewController.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/13/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import HealthKit


public class DailyQuantityScheduleTableViewController: SingleValueScheduleTableViewController {

    public var unit: HKUnit = HKUnit.gramUnit() {
        didSet {
            unitString = "\(unit)/U"
        }
    }

    override func preferredValueMinimumFractionDigits() -> Int {
        return unit.preferredMinimumFractionDigits
    }

}
