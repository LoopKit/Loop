//
//  UIImage.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIImage {
    private static func imageSuffixForLevel(_ level: Double?) -> String {
        let suffix: String

        switch level {
        case 0?:
            suffix = "0"
        case let x? where x <= 0.25:
            suffix = "25"
        case let x? where x <= 0.5:
            suffix = "50"
        case let x? where x <= 0.75:
            suffix = "75"
        case let x? where x <= 1:
            suffix = "100"
        default:
            suffix = "unknown"
        }

        return suffix
    }

    static func preMealImage(selected: Bool) -> UIImage? {
        return UIImage(named: selected ? "Pre-Meal Selected" : "Pre-Meal")
    }

    static func workoutImage(selected: Bool) -> UIImage? {
        return UIImage(named: selected ? "workout-selected" : "workout")
    }
}
