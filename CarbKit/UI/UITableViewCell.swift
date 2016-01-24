//
//  UITableViewCell.swift
//  CarbKit
//
//  Created by Nathan Racklyeft on 1/15/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension UITableViewCell {
    class var defaultIdentifier: String {
        return NSStringFromClass(self).componentsSeparatedByString(".").last!
    }
}
