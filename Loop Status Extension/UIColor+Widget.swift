//
//  UIColor+Widget.swift
//  Loop
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI

extension UIColor {
    @nonobjc static let axisLabelColor = subtitleLabelColor

    @nonobjc static let axisLineColor = subtitleLabelColor

    @nonobjc static let doseTintColor = UIColor(red: 255 / 255, green: 109 / 255, blue: 0, alpha: 1)

    @nonobjc static let freshColor = UIColor(red: 64 / 255, green: 219 / 255, blue: 89 / 255, alpha: 1)

    @nonobjc static let glucoseTintColor = UIColor(red: 0 / 255, green: 122 / 255, blue: 244 / 255, alpha: 1)

    @nonobjc static let gridColor = subtitleLabelColor

    @nonobjc static let pumpStatusNormal = UIColor(red: 100 / 255, green: 101 / 255, blue: 105 / 255, alpha: 1)

    @nonobjc static let subtitleLabelColor = UIColor(white: 0, alpha: 0.4)
}

extension UIColor: ChartColors {
    public var axisLineColor: UIColor {
        get {
            return UIColor.axisLineColor
        }
    }

    public var axisLabelColor: UIColor {
        get {
            return UIColor.axisLabelColor
        }
    }

    public var gridColor: UIColor {
        get {
            return UIColor.gridColor
        }
    }

    public var glucoseTintColor: UIColor {
        get {
            return UIColor.glucoseTintColor
        }
    }

    public var doseTintColor: UIColor {
        get {
            return UIColor.doseTintColor
        }
    }
}
