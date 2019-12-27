//
//  NSBundle.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation


extension Bundle {
    var shortVersionString: String {
        return object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    }

    var bundleDisplayName: String {
        return object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
    }

    var localizedNameAndVersion: String {
        return String(format: NSLocalizedString("%1$@ v%2$@", comment: "The format string for the app name and version number. (1: bundle name)(2: bundle version)"), bundleDisplayName, shortVersionString)
    }
    
    private var mainAppBundleIdentifier: String? {
        return object(forInfoDictionaryKey: "MainAppBundleIdentifier") as? String
    }

    var appGroupSuiteName: String {
        return object(forInfoDictionaryKey: "AppGroupIdentifier") as! String
    }

    var isAppExtension: Bool {
        return bundleURL.pathExtension == "appex"
    }

    var mainAppUrl: URL? {
        if let mainAppBundleIdentifier = mainAppBundleIdentifier {
            return URL(string: "\(mainAppBundleIdentifier)://")
        } else {
            return nil
        }
    }
    
    var gitRevision: String? {
        return object(forInfoDictionaryKey: "com-loopkit-Loop-git-revision") as? String
    }
    
    var gitBranch: String? {
        return object(forInfoDictionaryKey: "com-loopkit-Loop-git-branch") as? String
    }
    
    var sourceRoot: String? {
        return object(forInfoDictionaryKey: "com-loopkit-Loop-srcroot") as? String
    }
    
    var buildDateString: String? {
        return object(forInfoDictionaryKey: "com-loopkit-Loop-build-date") as? String
    }

    var xcodeVersion: String? {
        return object(forInfoDictionaryKey: "com-loopkit-Loop-xcode-version") as? String
    }
}
