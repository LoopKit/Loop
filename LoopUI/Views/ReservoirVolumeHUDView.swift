//
//  ReservoirVolumeHUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

public final class ReservoirVolumeHUDView: BaseHUDView {

    @IBOutlet private weak var levelMaskView: LevelMaskView!

    @IBOutlet private weak var volumeLabel: UILabel!

    override public func awakeFromNib() {
        super.awakeFromNib()

        tintColor = .unknownColor
        volumeLabel.isHidden = true

        accessibilityValue = NSLocalizedString("Unknown", comment: "Accessibility value for an unknown value")
    }

    public var reservoirLevel: Double? {
        didSet {
            levelMaskView.value = reservoirLevel ?? 1.0

            switch reservoirLevel {
            case .none:
                tintColor = .unknownColor
                volumeLabel.isHidden = true
            case let x? where x > 0.25:
                tintColor = .secondaryLabelColor
                volumeLabel.isHidden = true
            case let x? where x > 0.10:
                tintColor = .agingColor
                volumeLabel.textColor = tintColor
                volumeLabel.isHidden = false
            default:
                tintColor = .staleColor
                volumeLabel.textColor = tintColor
                volumeLabel.isHidden = false
            }
        }
    }

    private lazy var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        return formatter
    }()

    private lazy var numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0

        return formatter
    }()

    public func setReservoirVolume(volume: Double, at date: Date) {
        if let units = numberFormatter.string(from: NSNumber(value: volume)) {
            volumeLabel.text = String(format: NSLocalizedString("%@U", comment: "Format string for reservoir volume. (1: The localized volume)"), units)
            let time = timeFormatter.string(from: date)
            caption?.text = time

            accessibilityValue = String(format: NSLocalizedString("%1$@ units remaining at %2$@", comment: "Accessibility format string for (1: localized volume)(2: time)"), units, time)
        }
    }
}
