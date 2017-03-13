//
//  BatteryLevelHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


public final class BatteryLevelHUDView: LevelHUDView {

    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent

        return formatter
    }()

    public var batteryLevel: Double? {
        didSet {
            if let value = batteryLevel, let level = numberFormatter.string(from: NSNumber(value: value)) {
                caption.text = level
                accessibilityValue = level
            } else {
                caption.text = nil
            }

            level = batteryLevel
        }
    }

}
