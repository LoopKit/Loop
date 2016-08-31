//
//  UIColor.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIColor {
    @nonobjc static var tintColor: UIColor? = nil

    @nonobjc static let secondaryLabelColor = UIColor.HIGGrayColor()

    @nonobjc static let gridColor = UIColor(white: 193 / 255, alpha: 1)

    @nonobjc static let glucoseTintColor = UIColor.HIGTealBlueColor()

    @nonobjc static let IOBTintColor = UIColor.HIGOrangeColor()

    @nonobjc static let COBTintColor = UIColor.HIGYellowColor()

    @nonobjc static let doseTintColor = UIColor.HIGGreenColor()

    @nonobjc static let freshColor = UIColor.HIGGreenColor()

    @nonobjc static let agingColor = UIColor.HIGYellowColor()

    @nonobjc static let staleColor = UIColor.HIGRedColor()

    @nonobjc static let unknownColor = UIColor(red: 198 / 255, green: 199 / 255, blue: 201 / 255, alpha: 1)

    @nonobjc static let deleteColor = UIColor.HIGRedColor()

    // MARK: - HIG colors
    // See: https://developer.apple.com/ios/human-interface-guidelines/visual-design/color/

    private static func HIGTealBlueColor() -> UIColor {
        return UIColor(red: 90 / 255, green: 200 / 255, blue: 250 / 255, alpha: 1)
    }

    private static func HIGYellowColor() -> UIColor {
        return UIColor(red: 1, green: 204 / 255, blue: 0 / 255, alpha: 1)
    }

    private static func HIGOrangeColor() -> UIColor {
        return UIColor(red: 1, green: 149 / 255, blue: 0 / 255, alpha: 1)
    }

    private static func HIGPinkColor() -> UIColor {
        return UIColor(red: 1, green: 45 / 255, blue: 85 / 255, alpha: 1)
    }

    private static func HIGBlueColor() -> UIColor {
        return UIColor(red: 0, green: 122 / 255, blue: 1, alpha: 1)
    }

    private static func HIGGreenColor() -> UIColor {
        return UIColor(red: 76 / 255, green: 217 / 255, blue: 100 / 255, alpha: 1)
    }

    private static func HIGRedColor() -> UIColor {
        return UIColor(red: 1, green: 59 / 255, blue: 48 / 255, alpha: 1)
    }

    private static func HIGPurpleColor() -> UIColor {
        return UIColor(red: 88 / 255, green: 86 / 255, blue: 214 / 255, alpha: 1)
    }

    private static func HIGGrayColor() -> UIColor {
        return UIColor(red: 142 / 255, green: 143 / 255, blue: 147 / 255, alpha: 1)
    }

}
