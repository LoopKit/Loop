//
//  BolusProgressTableViewCell.swift
//  LoopUI
//
//  Created by Pete Schwamb on 3/11/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopUI
import HealthKit
import MKRingProgressView


public class BolusProgressTableViewCell: UITableViewCell {
    @IBOutlet weak var progressLabel: UILabel!
    
    @IBOutlet weak var tapToStopLabel: UILabel! {
        didSet {
            tapToStopLabel.text = NSLocalizedString("Tap to Stop", comment: "Message presented in the status row instructing the user to tap this row to stop a bolus")
        }
    }

    @IBOutlet weak var stopSquare: UIView! {
        didSet {
            stopSquare.layer.cornerRadius = 2
        }
    }

    @IBOutlet weak var progressIndicator: RingProgressView!

    public var totalUnits: Double? {
        didSet {
            updateProgress()
        }
    }

    public var deliveredUnits: Double? {
        didSet {
            updateProgress()
        }
    }

    private lazy var gradient = CAGradientLayer()

    private var doseTotalUnits: Double?

    private var disableUpdates: Bool = false

    lazy var insulinFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit())
        formatter.numberFormatter.minimumFractionDigits = 2
        return formatter
    }()

    override public func awakeFromNib() {
        super.awakeFromNib()

        gradient.frame = bounds
        backgroundView?.layer.insertSublayer(gradient, at: 0)
        updateColors()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        gradient.frame = bounds
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        updateColors()
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        updateColors()
    }

    private func updateColors() {
        progressIndicator.startColor = tintColor
        progressIndicator.endColor = tintColor
        stopSquare.backgroundColor = tintColor
        gradient.colors = [
            UIColor.cellBackgroundColor.withAlphaComponent(0).cgColor,
            UIColor.cellBackgroundColor.cgColor
        ]
    }

    private func updateProgress() {
        guard !disableUpdates, let totalUnits = totalUnits else {
            return
        }

        let totalUnitsQuantity = HKQuantity(unit: .internationalUnit(), doubleValue: totalUnits)
        let totalUnitsString = insulinFormatter.string(from: totalUnitsQuantity) ?? ""

        if let deliveredUnits = deliveredUnits {
            let deliveredUnitsQuantity = HKQuantity(unit: .internationalUnit(), doubleValue: deliveredUnits)
            let deliveredUnitsString = insulinFormatter.string(from: deliveredUnitsQuantity, includeUnit: false) ?? ""

            progressLabel.text = String(format: NSLocalizedString("Bolused %1$@ of %2$@", comment: "The format string for bolus progress. (1: delivered volume)(2: total volume)"), deliveredUnitsString, totalUnitsString)

            let progress = deliveredUnits / totalUnits
            UIView.animate(withDuration: 0.3) {
                self.progressIndicator.progress = progress
            }
        } else {
            progressLabel.text = String(format: NSLocalizedString("Bolusing %1$@", comment: "The format string for bolus in progress showing total volume. (1: total volume)"), totalUnitsString)
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()
        disableUpdates = true
        deliveredUnits = 0
        disableUpdates = false
        progressIndicator.progress = 0
        CATransaction.flush()
        progressLabel.text = ""
    }
}

extension BolusProgressTableViewCell: NibLoadable { }
