//
//  IdentifiableClass.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/22/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


public protocol IdentifiableClass: class {
    static var className: String { get }
}


extension IdentifiableClass {
    public static var className: String {
        return NSStringFromClass(self).components(separatedBy: ".").last!
    }
}
