//
//  SegmentedControlInputAccessoryView.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


class SegmentedControlInputAccessoryView: UIView {

    @IBOutlet weak var segmentedControl: UISegmentedControl? {
        didSet {
            segmentedControl?.setTitleTextAttributes(
                [NSFontAttributeName: UIFont.systemFontOfSize(40)],
                forState: .Normal
            )
        }
    }

}
