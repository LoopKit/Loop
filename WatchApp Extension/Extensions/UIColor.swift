//
//  UIColor.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIColor {
    @nonobjc static let tintColor = UIColor(red: 76 / 255, green: 217 / 255, blue: 100 / 255, alpha: 1)

    @nonobjc static let carbsColor = UIColor(red: 99 / 255, green: 218 / 255, blue: 56 / 255, alpha: 1)

    @nonobjc static let darkCarbsColor = UIColor.carbsColor.withAlphaComponent(0.14)

    // MARK: - HIG colors
    // See: https://developer.apple.com/watch/human-interface-guidelines/visual-design/#color

    private static func HIGPinkColor() -> UIColor {
        return UIColor(red: 250 / 255, green: 17 / 255, blue: 79 / 255, alpha: 1)
    }

    private static func HIGPinkColorDark() -> UIColor {
        return HIGPinkColor().withAlphaComponent(0.17)
    }

    private static func HIGRedColor() -> UIColor {
        return UIColor(red: 1, green: 59 / 255, blue: 48 / 255, alpha: 1)
    }

    private static func HIGRedColorDark() -> UIColor {
        return HIGRedColor().withAlphaComponent(0.17)
    }

    private static func HIGOrangeColor() -> UIColor {
        return UIColor(red: 1, green: 149 / 255, blue: 0, alpha: 1)
    }

    private static func HIGOrangeColorDark() -> UIColor {
        return HIGOrangeColor().withAlphaComponent(0.15)
    }

    private static func HIGYellowColor() -> UIColor {
        return UIColor(red: 1, green: 230 / 255, blue: 32 / 255, alpha: 1)
    }

    private static func HIGYellowColorDark() -> UIColor {
        return HIGYellowColor().withAlphaComponent(0.14)
    }

    private static func HIGGreenColor() -> UIColor {
        return UIColor(red: 4 / 255, green: 222 / 255, blue: 113 / 255, alpha: 1)
    }

    private static func HIGGreenColorDark() -> UIColor {
        return HIGGreenColor().withAlphaComponent(0.14)
    }
}
