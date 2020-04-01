//
//  UIColor.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/20/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIColor {
    static let tintColor = UIColor(named: "tint")!

    static let carbsColor = UIColor(named: "carbs")!

    // Equivalent to carbsColor with alpha 0.14 on a black background
    static let darkCarbsColor = UIColor(named: "carbs-dark")!

    static let glucose = UIColor(named: "glucose")!

    // Equivalent to glucoseColor with alpha 0.14 on a black background
    static let darkGlucose = UIColor(named: "glucose-dark")!

    static let insulin = UIColor(named: "insulin")!

    static let darkInsulin = UIColor(named: "insulin-dark")!

    static let overrideColor = UIColor(named: "workout")!

    // Equivalent to workoutColor with alpha 0.14 on a black background
    static let darkOverrideColor = UIColor(named: "workout-dark")!

    static let disabledButtonColor = UIColor.gray

    static let darkDisabledButtonColor = UIColor.disabledButtonColor.withAlphaComponent(0.14)

    static let chartLabel = HIGWhiteColor()

    static let chartNowLine = HIGWhiteColor().withAlphaComponent(0.2)

    static let chartPlatter = HIGWhiteColorDark()
   
    static let agingColor = HIGYellowColor()
    
    static let staleColor = HIGRedColor()
    
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

    private static func HIGWhiteColor() -> UIColor {
        return UIColor(red: 242 / 255, green: 244 / 255, blue: 1, alpha: 1)
    }

    private static func HIGWhiteColorDark() -> UIColor {
        // Equivalent to HIGWhiteColor().withAlphaComponent(0.14) on black
        return UIColor(red: 33 / 255, green: 34 / 255, blue: 35 / 255, alpha: 1)
    }
}
