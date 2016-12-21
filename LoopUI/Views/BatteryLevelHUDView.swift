//
//  BatteryLevelHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


public final class BatteryLevelHUDView: BaseHUDView {

    @IBOutlet private weak var levelMaskView: LevelMaskView!

    override public func awakeFromNib() {
        super.awakeFromNib()

        tintColor = .unknownColor

        accessibilityValue = NSLocalizedString("Unknown", comment: "Accessibility value for an unknown value")
    }

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

            switch batteryLevel {
            case .none:
                tintColor = .unknownColor
            case let x? where x > 0.25:
                tintColor = .secondaryLabelColor
            case let x? where x > 0.10:
                tintColor = .agingColor
            default:
                tintColor = .staleColor
            }

            levelMaskView.value = batteryLevel ?? 1.0
        }
    }

}
