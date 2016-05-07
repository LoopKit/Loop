//
//  HUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class HUDView: UIView {

    @IBOutlet var caption: UILabel! {
        didSet {
            caption?.text = "—"
        }
    }

}
