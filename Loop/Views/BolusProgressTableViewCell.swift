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
import LoopAlgorithm
import MKRingProgressView


public class BolusProgressTableViewCell: UITableViewCell {
    
    public enum Configuration {
        case starting
        case bolusing(delivered: Double?, ofTotalVolume: Double)
        case canceling
        case canceled(delivered: Double, ofTotalVolume: Double, automatic: Bool)
    }

    public var onInfoTapped: (() -> Void)?
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var paddedView: UIView!
    @IBOutlet weak var progressIndicator: RingProgressView!
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

    private lazy var infoButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "info.circle"), for: .normal)
        button.accessibilityLabel = NSLocalizedString("About this canceled bolus", comment: "Accessibility label for the info button on a canceled automatic bolus")
        button.accessibilityIdentifier = "button_CanceledBolusInfo"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addTarget(self, action: #selector(infoTapped), for: .touchUpInside)
        return button
    }()

    @objc private func infoTapped() {
        onInfoTapped?()
    }

    public var configuration: Configuration? {
        didSet {
            updateProgress()
        }
    }

    lazy var insulinFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit)
        formatter.numberFormatter.minimumFractionDigits = 2
        return formatter
    }()

    override public func awakeFromNib() {
        super.awakeFromNib()

        (progressLabel.superview as? UIStackView)?.addArrangedSubview(infoButton)

        paddedView.layer.masksToBounds = true
        paddedView.layer.cornerRadius = 10
        paddedView.layer.borderWidth = 1
        paddedView.layer.borderColor = UIColor.systemGray5.cgColor
        
        updateColors()
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
    }

    private func updateProgress() {
        guard let configuration else {
            progressIndicator.isHidden = true
            activityIndicator.isHidden = true
            tapToStopLabel.isHidden = true
            infoButton.isHidden = true
            return
        }

        infoButton.isHidden = true
        
        switch configuration {
        case .starting:
            progressIndicator.isHidden = true
            activityIndicator.isHidden = false
            tapToStopLabel.isHidden = true
            
            progressLabel.text = NSLocalizedString("Starting Bolus", comment: "The title of the cell indicating a bolus is being sent")
            progressLabel.accessibilityIdentifier = "text_BolusStarting"
        case let .bolusing(delivered, totalVolume):
            progressIndicator.isHidden = false
            activityIndicator.isHidden = true
            tapToStopLabel.isHidden = false
            tapToStopLabel.accessibilityIdentifier = "text_TapToStop"
            
            let totalUnitsQuantity = LoopQuantity(unit: .internationalUnit, doubleValue: totalVolume)
            let totalUnitsString = insulinFormatter.string(from: totalUnitsQuantity) ?? ""
            
            if let delivered {
                let deliveredUnitsQuantity = LoopQuantity(unit: .internationalUnit, doubleValue: delivered)
                let deliveredUnitsString = insulinFormatter.string(from: deliveredUnitsQuantity, includeUnit: false) ?? ""
                
                progressLabel.text = String(format: NSLocalizedString("Bolused %1$@ of %2$@", comment: "The format string for bolus progress. (1: delivered volume)(2: total volume)"), deliveredUnitsString, totalUnitsString)
                progressLabel.accessibilityIdentifier = "text_BolusingProgress"
                
                let progress = delivered / totalVolume
                
                UIView.animate(withDuration: 0.3) {
                    self.progressIndicator.progress = progress
                }
            } else {
                progressLabel.text = String(format: NSLocalizedString("Bolusing %1$@", comment: "The format string for bolus in progress showing total volume. (1: total volume)"), totalUnitsString)
                progressLabel.accessibilityIdentifier = "text_BolusingProgress"
            }
        case .canceling:
            progressIndicator.isHidden = true
            activityIndicator.isHidden = false
            tapToStopLabel.isHidden = true
            
            progressLabel.text = NSLocalizedString("Canceling Bolus", comment: "The title of the cell indicating a bolus is being canceled")
            progressLabel.accessibilityIdentifier = "text_BolusCanceling"
        case let .canceled(delivered, totalVolume, automatic):
            progressIndicator.isHidden = true
            activityIndicator.isHidden = true
            tapToStopLabel.isHidden = true
            infoButton.isHidden = !automatic
            
            let totalUnitsQuantity = LoopQuantity(unit: .internationalUnit, doubleValue: totalVolume)
            let totalUnitsString = insulinFormatter.string(from: totalUnitsQuantity) ?? ""
            
            let deliveredUnitsQuantity = LoopQuantity(unit: .internationalUnit, doubleValue: delivered)
            let deliveredUnitsString = insulinFormatter.string(from: deliveredUnitsQuantity, includeUnit: false) ?? ""
            
            progressLabel.text = String(format: NSLocalizedString("Bolus Canceled: Delivered %1$@ of %2$@", comment: "The title of the cell indicating a bolus has been canceled. (1: delivered volume)(2: total volume)"), deliveredUnitsString, totalUnitsString)
            progressLabel.accessibilityIdentifier = "text_BolusCanceled"
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()
        onInfoTapped = nil
        configuration = nil
        progressIndicator.progress = 0
        CATransaction.flush()
        progressLabel.text = ""
    }
}

extension BolusProgressTableViewCell: NibLoadable { }
