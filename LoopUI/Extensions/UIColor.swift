//
//  UIColor.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

// MARK: - Color palette for common elements
extension UIColor {
    @nonobjc static let carbs = UIColor(named: "carbs") ?? systemGreen
    
    @nonobjc static let fresh = UIColor(named: "fresh") ?? HIGGreenColor()

    @nonobjc static let glucose = UIColor(named: "glucose") ?? systemTeal
    
    @nonobjc static let insulin = UIColor(named: "insulin") ?? systemOrange

    // The loopAccent color is intended to be use as the app accent color.
    @nonobjc public static let loopAccent = UIColor(named: "accent") ?? systemBlue
    
    @nonobjc public static let warning = UIColor(named: "warning") ?? systemYellow
}

// MARK: - Context for colors
extension UIColor {
    @nonobjc public static let agingColor = warning
    
    @nonobjc public static let axisLabelColor = secondaryLabel
    
    @nonobjc public static let axisLineColor = clear
    
    @nonobjc public static let cellBackgroundColor = secondarySystemBackground
    
    @nonobjc public static let carbTintColor = carbs
    
    @nonobjc public static let critical = systemRed
    
    @nonobjc public static let destructive = critical
    
    @nonobjc public static let freshColor = fresh

    @nonobjc public static let glucoseTintColor = glucose
    
    @nonobjc public static let gridColor = systemGray3
    
    @nonobjc public static let invalid = critical

    @nonobjc public static let insulinTintColor = insulin
    
    @nonobjc public static let pumpStatusNormal = insulin
    
    @nonobjc public static let staleColor = critical
    
    @nonobjc public static let unknownColor = systemGray4
}
