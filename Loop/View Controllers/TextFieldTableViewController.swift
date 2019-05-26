//
//  TextFieldTableViewController.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/31/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import LoopKitUI
import HealthKit


/// Convenience static constructors used to contain common configuration
extension TextFieldTableViewController {
    typealias T = TextFieldTableViewController
    
    private static let valueNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()

        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2

        return formatter
    }()
}
