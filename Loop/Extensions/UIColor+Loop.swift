//
//  UIColor+Loop.swift
//  Loop
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI

extension UIColor {
    @nonobjc static let axisLabelColor = secondaryLabelColor

    @nonobjc static let axisLineColor = UIColor.clear

    @nonobjc static let doseTintColor = UIColor.HIGOrangeColor()

    @nonobjc static let freshColor = UIColor.HIGGreenColor()

    @nonobjc static let glucoseTintColor = UIColor(red: 0 / 255, green: 176 / 255, blue: 255 / 255, alpha: 1)

    @nonobjc static let gridColor = UIColor(white: 193 / 255, alpha: 1)
    
    @nonobjc static let pumpStatusNormal = secondaryLabelColor
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
