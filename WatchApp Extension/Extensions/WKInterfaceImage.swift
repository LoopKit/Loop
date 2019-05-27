//
//  WKInterfaceImage.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit

enum LoopImage: String {
    case fresh
    case aging
    case stale
    case unknown

    var imageName: String {
        return "loop_\(rawValue)"
    }
}


extension WKInterfaceImage {
    func setLoopImage(_ loopImage: LoopImage) {
        setImageNamed(loopImage.imageName)
    }
}
