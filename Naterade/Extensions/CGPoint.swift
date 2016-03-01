//
//  CGPoint.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


extension CGPoint {
    /**
     Rounds the coordinates to whole-pixel values

     - parameter scale: The display scale to use. Defaults to the main screen scale.
     */
    mutating func makeIntegralInPlaceWithDisplayScale(scale: CGFloat = UIScreen.mainScreen().scale) {
        x = round(x * scale) / scale
        y = round(y * scale) / scale
    }
}
