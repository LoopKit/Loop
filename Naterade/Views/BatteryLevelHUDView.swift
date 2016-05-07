//
//  BatteryLevelHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class BatteryLevelHUDView: HUDView {

    @IBOutlet private var imageView: UIImageView!

    private lazy var numberFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .PercentStyle

        return formatter
    }()


    var batteryLevel: Double? {
        didSet {
            if let value = batteryLevel, level = numberFormatter.stringFromNumber(value) {
                caption.text = level
            } else {
                caption.text = nil
            }

            imageView.image = UIImage.batteryHUDImageWithLevel(batteryLevel)
        }
    }

}
