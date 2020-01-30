//
//  NibLoadable.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/2/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit
import LoopCore


public protocol NibLoadable: IdentifiableClass {
    static func nib() -> UINib
}


extension NibLoadable {
    public static func nib() -> UINib {
        return UINib(nibName: className, bundle: Bundle(for: self))
    }
}
