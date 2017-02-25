//
//  HUDView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/1/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

public class BaseHUDView: UIView {

    @IBOutlet weak var caption: UILabel! {
        didSet {
            caption?.text = "—"
        }
    }

}
