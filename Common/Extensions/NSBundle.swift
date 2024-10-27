//
//  NSBundle.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

extension Bundle {
    var fullVersionString: String {
        return "\(shortVersionString) (\(version))"
    }

    var shortVersionString: String {
        return object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    }

    var version: String {
        return object(forInfoDictionaryKey: "CFBundleVersion") as! String
    }

    var bundleDisplayName: String {
        return object(forInfoDictionaryKey: "CFBundleDisplayName") as! String
    }

    var localizedNameAndVersion: String {
        return String(format: NSLocalizedString("%1$@ v%2$@", comment: "The format string for the app name and version number. (1: bundle name)(2: bundle version)"), bundleDisplayName, fullVersionString)
    }
    
    private var mainAppBundleIdentifier: String? {
        return object(forInfoDictionaryKey: "MainAppBundleIdentifier") as? String
    }

    var appGroupSuiteName: String {
        return object(forInfoDictionaryKey: "AppGroupIdentifier") as! String
    }
    
    var appStoreURL: String? {
        return object(forInfoDictionaryKey: "AppStoreURL") as? String
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
    
    var localCacheDuration: TimeInterval {
        guard let localCacheDurationDaysString = object(forInfoDictionaryKey: "LoopLocalCacheDurationDays") as? String,
            let localCacheDurationDays = Double(localCacheDurationDaysString) else {
                return .days(1)
        }
        return .days(localCacheDurationDays)
    }

    var hostIdentifier: String {
        var identifier = bundleIdentifier ?? "com.loopkit.Loop"
        let components = identifier.components(separatedBy: ".")
        // DIY Loop has bundle identifiers like com.UY653SP37Q.loopkit.Loop
        if components[2] == "loopkit" && components[3] == "Loop" {
            identifier = "com.loopkit.Loop"
        }
        return identifier
    }

    var hostVersion: String {
        var semanticVersion = shortVersionString

        while semanticVersion.split(separator: ".").count < 3 {
            semanticVersion += ".0"
        }

        semanticVersion += "+\(Bundle.main.version)"

        return semanticVersion
    }
}

