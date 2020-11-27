//
//  CarbEntryTableViewCell.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit

class CarbEntryTableViewCell: UITableViewCell {

    @IBOutlet private weak var clampedProgressView: UIProgressView!

    @IBOutlet private weak var observedProgressView: UIProgressView!

    @IBOutlet weak var valueLabel: UILabel!

    @IBOutlet weak var dateLabel: UILabel!

    @IBOutlet private weak var observedValueLabel: UILabel!

    @IBOutlet private weak var observedDateLabel: UILabel!

    @IBOutlet private weak var disclosureImage: UIImageView!
    
    var isEditable: Bool = true {
        didSet {
            disclosureImage.isHidden = !isEditable
        }
    }

    var clampedProgress: Float {
        get {
            return clampedProgressView.progress
        }
        set {
            clampedProgressView.progress = newValue
            clampedProgressView.isHidden = clampedProgress <= 0
        }
    }

    var observedProgress: Float {
        get {
            return observedProgressView.progress
        }
        set {
            observedProgressView.progress = newValue
            observedProgressView.isHidden = observedProgress <= 0
        }
    }

    var observedValueText: String? {
        get {
            return observedValueLabel.text
        }
        set {
            observedValueLabel.text = newValue
            if newValue != nil {
                observedValueLabel.superview?.isHidden = false
            }
        }
    }

    var observedDateText: String? {
        get {
            return observedDateLabel.text
        }
        set {
            observedDateLabel.text = newValue
            if newValue != nil {
                observedDateLabel.superview?.isHidden = false
            }
        }
    }

    var observedValueTextColor: UIColor {
        get {
            return observedValueLabel.textColor
        }
        set {
            observedValueLabel.textColor = newValue
        }
    }

    var observedDateTextColor: UIColor {
        get {
            return observedDateLabel.textColor
        }
        set {
            observedDateLabel.textColor = newValue
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        contentView.layoutMargins.left = separatorInset.left
        contentView.layoutMargins.right = separatorInset.left
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        resetViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        resetViews()
    }

    private func resetViews() {
        observedProgress = 0
        clampedProgress = 0
        valueLabel.text = nil
        dateLabel.text = nil
        observedValueText = nil
        observedDateText = nil
        observedValueLabel.superview?.isHidden = true
    }
}
