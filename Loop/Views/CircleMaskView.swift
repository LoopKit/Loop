//
//  CircleMaskView.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit

class CircleMaskView: UIView {

    override func layoutSubviews() {
        super.layoutSubviews()

        self.layer.cornerRadius = self.frame.height / 2
    }

}
