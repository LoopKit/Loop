//
//  ReservoirVolumeHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

final class ReservoirVolumeHUDView: HUDView {

    @IBOutlet private var levelMaskView: LevelMaskView!

    @IBOutlet private var volumeLabel: UILabel!

    override func awakeFromNib() {
        super.awakeFromNib()

        tintColor = .unknownColor
        volumeLabel.hidden = true
    }

    var reservoirLevel: Double? {
        didSet {
            levelMaskView.value = reservoirLevel ?? 1.0

            switch reservoirLevel {
            case .None:
                tintColor = .unknownColor
                volumeLabel.hidden = true
            case let x? where x > 0.25:
                tintColor = .secondaryLabelColor
                volumeLabel.hidden = true
            case let x? where x > 0.10:
                tintColor = .agingColor
                volumeLabel.textColor = tintColor
                volumeLabel.hidden = false
            default:
                tintColor = .staleColor
                volumeLabel.textColor = tintColor
                volumeLabel.hidden = false
            }
        }
    }

    var lastUpdated: NSDate? {
        didSet {
            if let date = lastUpdated {
                caption?.text = timeFormatter.stringFromDate(date)
            }
        }
    }

    private lazy var timeFormatter: NSDateFormatter = {
        let formatter = NSDateFormatter()
        formatter.dateStyle = .NoStyle
        formatter.timeStyle = .ShortStyle

        return formatter
    }()

    private lazy var numberFormatter: NSNumberFormatter = {
        let formatter = NSNumberFormatter()
        formatter.numberStyle = .DecimalStyle
        formatter.maximumFractionDigits = 0

        return formatter
    }()

    var reservoirVolume: Double? {
        didSet {
            if let volume = reservoirVolume, units = numberFormatter.stringFromNumber(volume) {
                volumeLabel.text = String(format: NSLocalizedString("%@U", comment: "Format string for reservoir volume. (1: The localized volume)"), units)
            }
        }
    }

}
