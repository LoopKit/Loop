//
//  UIColor.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIColor {
    @nonobjc static var tintColor = UIColor.HIGOrangeColor()

    @nonobjc static let secondaryLabelColor: UIColor = UIColor(red: 142 / 255, green: 142 / 255, blue: 147 / 255, alpha: 1)

    @nonobjc static let gridColor = UIColor(white: 193 / 255, alpha: 1)

    @nonobjc static let glucoseTintColor: UIColor = UIColor.HIGLightBlueColor()

    @nonobjc static let IOBTintColor: UIColor = UIColor.HIGOrangeColor()

    @nonobjc static let COBTintColor: UIColor = UIColor.HIGYellowColor()

    @nonobjc static let doseTintColor: UIColor = UIColor.HIGGreenColor()

    @nonobjc static let freshColor: UIColor = UIColor.HIGGreenColor()

    @nonobjc static let agingColor: UIColor = UIColor.HIGYellowColor()

    @nonobjc static let staleColor: UIColor = UIColor.HIGRedColor()

    @nonobjc static let unknownColor: UIColor = UIColor.HIGGrayColor().colorWithAlphaComponent(0.5)

    // MARK: - HIG colors
    // See: https://developer.apple.com/library/ios/documentation/UserExperience/Conceptual/MobileHIG/ColorImagesText.html

    private static func HIGLightBlueColor() -> UIColor {
        return UIColor(red: 96 / 255, green: 201 / 255, blue: 248 / 255, alpha: 1)
    }

    private static func HIGYellowColor() -> UIColor {
        return UIColor(red: 1, green: 203 / 255, blue: 47 / 255, alpha: 1)
    }

    private static func HIGOrangeColor() -> UIColor {
        return UIColor(red: 254 / 255, green: 149 / 255, blue: 38 / 255, alpha: 1)
    }

    private static func HIGPinkColor() -> UIColor {
        return UIColor(red: 253 / 255, green: 50 / 255, blue: 89 / 255, alpha: 1)
    }

    private static func HIGBlueColor() -> UIColor {
        return UIColor(red: 22 / 255, green: 127 / 255, blue: 252 / 255, alpha: 1)
    }

    private static func HIGGreenColor() -> UIColor {
        return UIColor(red: 83 / 255, green: 216 / 255, blue: 106 / 255, alpha: 1)
    }

    private static func HIGRedColor() -> UIColor {
        return UIColor(red: 253 / 255, green: 61 / 255, blue: 57 / 255, alpha: 1)
    }

    private static func HIGGrayColor() -> UIColor {
        return UIColor(red: 142 / 255, green: 143 / 255, blue: 147 / 255, alpha: 1)
    }

}
