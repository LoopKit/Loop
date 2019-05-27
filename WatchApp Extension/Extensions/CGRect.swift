//
//  CGRect.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 10/17/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import CoreGraphics


extension CGRect {
    func alignedToScreenScale(_ screenScale: CGFloat) -> CGRect {
        let factor = 1 / screenScale

        return CGRect(
            x: origin.x.floored(to: factor),
            y: origin.y.floored(to: factor),
            width: size.width.ceiled(to: factor),
            height: size.height.ceiled(to: factor)
        )
    }
}
