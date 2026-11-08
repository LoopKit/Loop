//
//  RecentGlucoseTableViewCell.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2025-10-27.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI

public class RecentGlucoseTableViewCell: UITableViewCell {
    @IBOutlet weak var paddedView: UIView!
    @IBOutlet weak var title: UILabel!
    @IBOutlet weak var caption: UILabel!
    
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

extension RecentGlucoseTableViewCell: NibLoadable { }
