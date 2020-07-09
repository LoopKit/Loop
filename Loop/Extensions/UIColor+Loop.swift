//
//  UIColor+Loop.swift
//  Loop
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import UIKit


extension UIColor {
    @nonobjc static let axisLabelColor = secondaryLabelColor

    @nonobjc static let axisLineColor = UIColor.clear

    @nonobjc static let doseTintColor = UIColor.systemOrange

    @nonobjc static let freshColor = UIColor.HIGGreenColor()

    @nonobjc static let glucoseTintColor: UIColor = {
        if #available(iOS 13.0, *) {
            return UIColor(dynamicProvider: { (traitCollection) in
                // If we're in accessibility mode, return the system color
                guard case .normal = traitCollection.accessibilityContrast else {
                    return .systemBlue
                }

                switch traitCollection.userInterfaceStyle {
                case .unspecified, .light:
                    return UIColor(red: 0 / 255, green: 176 / 255, blue: 255 / 255, alpha: 1)
                case .dark:
                    return UIColor(red: 10 / 255, green: 186 / 255, blue: 255 / 255, alpha: 1)
                @unknown default:
                    return UIColor(red: 0 / 255, green: 176 / 255, blue: 255 / 255, alpha: 1)
                }
            })
        } else {
            return UIColor(red: 0 / 255, green: 176 / 255, blue: 255 / 255, alpha: 1)
        }
    }()

    @nonobjc static let gridColor: UIColor = {
        if #available(iOS 13.0, *) {
            return .systemGray3
        } else {
            return UIColor(red: 0 / 255, green: 176 / 255, blue: 255 / 255, alpha: 1)
        }
    }()
    
    @nonobjc static let pumpStatusNormal = UIColor.systemGray
}
