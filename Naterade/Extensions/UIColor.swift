//
//  UIColor.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIColor {
    static func tintColor() -> UIColor {
        return UIColor(red: 1.0, green: 149.0 / 255.0, blue: 0, alpha: 1.0)
    }

    static func darkTintColor() -> UIColor {
        return tintColor().colorWithAlphaComponent(0.15)
    }
}
