//
//  TouchAndPanGestureRecognizer.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/22/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import UIKit.UIGestureRecognizerSubclass


class TouchAndPanGestureRecognizer: UIPanGestureRecognizer {
    /**
    Set state to Began on first touch, rather than after first move

    See: http://stackoverflow.com/a/22937365
    */
    override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent) {
        guard case state = UIGestureRecognizerState.Possible else {
            return
        }

        super.touchesBegan(touches, withEvent: event)
        state = .Began
    }
}
