//
//  OTPNavigatioController.swift
//  Loop
//
//  Created by Jose Paredes on 3/28/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import UIKit

class OTPNavigationController: UINavigationController {
    
    // portrait only

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
       return .portrait
    }
    override public var shouldAutorotate: Bool {
       return false
    }
    override public var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
    
}
