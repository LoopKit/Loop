//
//  WKInterfaceImage.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit

enum LoopImage: String {
    case Fresh
    case Aging
    case Stale
    case Unknown
}


extension WKInterfaceImage {
    func setLoopImage(loopImage: LoopImage) {
        setImageNamed("loop_\(loopImage.rawValue.lowercaseString)")
    }
}