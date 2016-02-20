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

    @nonobjc static let glucoseTintColor: UIColor = UIColor.HIGBlueColor()

    // MARK: - HIG colors
    // See: https://developer.apple.com/library/ios/documentation/UserExperience/Conceptual/MobileHIG/ColorImagesText.html

    private static func HIGLightBlueColor() -> UIColor {
        return UIColor(red: 22.0 / 255.0, green: 127.0 / 255.0, blue: 252.0 / 255.0, alpha: 1.0)
    }

    private static func HIGYellowColor() -> UIColor {
        return UIColor(red: 1, green: 203.0 / 255.0, blue: 47.0 / 255.0, alpha: 1.0)
    }

    private static func HIGOrangeColor() -> UIColor {
        return UIColor(red: 254.0 / 255.0, green: 149.0 / 255.0, blue: 38.0 / 255.0, alpha: 1.0)
    }

    private static func HIGPinkColor() -> UIColor {
        return UIColor(red: 253.0 / 255.0, green: 50.0 / 255.0, blue: 89.0 / 255.0, alpha: 1.0)
    }

    private static func HIGBlueColor() -> UIColor {
        return UIColor(red: 22.0 / 255.0, green: 127.0 / 255.0, blue: 252.0 / 255.0, alpha: 1.0)
    }

    private static func HIGGreenColor() -> UIColor {
        return UIColor(red: 83.0 / 255.0, green: 216.0 / 255.0, blue: 106.0 / 255.0, alpha: 1.0)
    }

    private static func HIGRedColor() -> UIColor {
        return UIColor(red: 253.0 / 255.0, green: 61.0 / 255.0, blue: 57.0 / 255.0, alpha: 1.0)
    }
}
