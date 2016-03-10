//
//  NateradeTests.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 3/9/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
import Foundation

public typealias JSONDictionary = [String: AnyObject]


extension XCTestCase {
    public var bundle: NSBundle {
        return NSBundle(forClass: self.dynamicType)
    }

    public func loadFixture<T>(resourceName: String) -> T {
        let path = bundle.pathForResource(resourceName, ofType: "json")!
        return try! NSJSONSerialization.JSONObjectWithData(NSData(contentsOfFile: path)!, options: []) as! T
    }
}
