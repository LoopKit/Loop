//
//  NSBundle.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension NSBundle {
    var shortVersionString: String {
        return objectForInfoDictionaryKey("CFBundleShortVersionString") as! String
    }

    var bundleDisplayName: String {
        return objectForInfoDictionaryKey("CFBundleDisplayName") as! String
    }

    var localizedNameAndVersion: String {
        return String(format: NSLocalizedString("%1$@ v%2$@", comment: "The format string for the app name and version number. (1: bundle name)(2: bundle version)"), bundleDisplayName, shortVersionString)
    }
}
