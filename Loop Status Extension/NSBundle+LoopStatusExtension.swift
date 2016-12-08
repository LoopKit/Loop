//
//  NSBundle+LoopStatusExtension.swift
//  Loop
//
//  Created by Bharat Mediratta on 12/7/16.
//  Copyright © 2016 LoopKit Authors. All rights reserved.
//

import Foundation

extension Bundle {
    static var appGroupSuiteName: String {
        // Use a specific view controller from Loop Status Extension to make sure that we get the appropriate bundle
        return "group." + (Bundle(for: StatusViewController.self).object(forInfoDictionaryKey: "MainAppBundleIdentifier") as! String)
    }
}
