//
//  UIColor.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 1/23/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UIColor {
    @nonobjc static let secondaryLabelColor: UIColor = {
        if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
            return UIColor.secondaryLabel
        } else {
            return UIColor.systemGray
        }
    }()

    @nonobjc static let cellBackgroundColor: UIColor = {
        if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
            return .secondarySystemBackground
        } else {
            return UIColor(white: 239 / 255, alpha: 1)
        }
    }()

    @nonobjc static let IOBTintColor = UIColor.systemOrange

    @nonobjc static let COBTintColor: UIColor = {
        if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
            return UIColor(dynamicProvider: { (traitCollection) in
                // If we're in accessibility mode, return the system color
                guard case .normal = traitCollection.accessibilityContrast else {
                    return .systemGreen
                }

                switch traitCollection.userInterfaceStyle {
                case .unspecified, .light:
                    return UIColor(red: 99 / 255, green: 218 / 255, blue: 56 / 255, alpha: 1)
                case .dark:
                    return UIColor(red: 89 / 255, green: 228 / 255, blue: 51 / 255, alpha: 1)
                @unknown default:
                    return UIColor(red: 99 / 255, green: 218 / 255, blue: 56 / 255, alpha: 1)
                }
            })
        } else {
            return UIColor(red: 99 / 255, green: 218 / 255, blue: 56 / 255, alpha: 1)
        }
    }()

    @nonobjc static let agingColor = UIColor.systemYellow

    @nonobjc static let staleColor = UIColor.systemRed

    @nonobjc static let unknownColor: UIColor = {
        if #available(iOSApplicationExtension 13.0, iOS 13.0, *) {
            return .systemGray4
        } else {
            return UIColor(red: 198 / 255, green: 199 / 255, blue: 201 / 255, alpha: 1)
        }
    }()

    static let delete = UIColor.systemRed
}
