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

    func imageName(isClosedLoop: Bool) -> String {
        let suffix = isClosedLoop ? "closed" : "open"
        return "loop_\(rawValue)_\(suffix)"
    }
}


extension WKInterfaceImage {
    func setLoopImage(isClosedLoop: Bool, _ loopImage: LoopImage) {
        setImageNamed(loopImage.imageName(isClosedLoop: isClosedLoop))
    }
}
