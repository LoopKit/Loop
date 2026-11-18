//
//  InsulinSuspendedTableViewCell.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2025-10-27.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI

public class InsulinSuspendedTableViewCell: UITableViewCell {
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var paddedView: UIView!
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var tapToResumeLabel: UILabel!
    
    override public func awakeFromNib() {
        super.awakeFromNib()

        paddedView.layer.masksToBounds = true
        paddedView.layer.cornerRadius = 10
        paddedView.layer.borderWidth = 1

        updateBorderColor()
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingColorAppearance) { (cell: Self, _: UITraitCollection) in
            cell.updateBorderColor()
        }
    }

    private func updateBorderColor() {
        paddedView.layer.borderColor = UIColor.systemGray5.resolvedColor(with: traitCollection).cgColor
    }
}

extension InsulinSuspendedTableViewCell: NibLoadable { }
