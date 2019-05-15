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

    @nonobjc static let cellBackgroundColor = UIColor(white: 239 / 255, alpha: 1)

    @nonobjc static let IOBTintColor = UIColor.HIGOrangeColor()

    @nonobjc static let COBTintColor = UIColor(red: 99 / 255, green: 218 / 255, blue: 56 / 255, alpha: 1)

    @nonobjc static let agingColor = UIColor.HIGYellowColor()

    @nonobjc static let staleColor = UIColor.HIGRedColor()

    @nonobjc static let unknownColor = UIColor(red: 198 / 255, green: 199 / 255, blue: 201 / 255, alpha: 1)

    static let delete = UIColor.HIGRedColor()
    
    //DarkMode
    public func lighter(by percentage: CGFloat = 30.0) -> UIColor? {
        return self.adjust(by: abs(percentage) )
    }
    
    public func darker(by percentage: CGFloat = 30.0) -> UIColor? {
        return self.adjust(by: -1 * abs(percentage) )
    }
    
    public func adjust(by percentage: CGFloat = 30.0) -> UIColor? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if self.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return UIColor(red: min(red + percentage/100, 1.0),
                           green: min(green + percentage/100, 1.0),
                           blue: min(blue + percentage/100, 1.0),
                           alpha: alpha)
        }
        return nil
    }
    //DarkMode
}
