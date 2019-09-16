//
//  UIColor+HIG.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIColor {
    // MARK: - HIG colors
    // See: https://developer.apple.com/ios/human-interface-guidelines/visual-design/color/

    // HIG Green has changed for iOS 13. This is the legacy color.
    static func HIGGreenColor() -> UIColor {
        return UIColor(red: 76 / 255, green: 217 / 255, blue: 100 / 255, alpha: 1)
    }
}
