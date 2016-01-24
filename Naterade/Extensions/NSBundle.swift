//
//  NSBundle.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 9/7/15.
//  Copyright © 2015 Nathan Racklyeft. All rights reserved.
//

import Foundation

extension NSBundle {
    var shortVersionString: String! {
        return objectForInfoDictionaryKey("CFBundleShortVersionString") as? String
    }
}