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

    @nonobjc static let deleteColor = UIColor.HIGRedColor()
}
