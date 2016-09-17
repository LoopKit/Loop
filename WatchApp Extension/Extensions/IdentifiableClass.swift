//
//  IdentifiableClass.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 2/9/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


protocol IdentifiableClass: class {
    static var className: String { get }
}


extension IdentifiableClass {
    static var className: String {
        return NSStringFromClass(self).components(separatedBy: ".").last!
    }
}
