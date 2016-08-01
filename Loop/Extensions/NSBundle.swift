//
//  NSBundle.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation

extension NSBundle {
    var shortVersionString: String! {
        return objectForInfoDictionaryKey("CFBundleShortVersionString") as? String
    }
    
    private var remoteSettingsPath: String? {
        return NSBundle.mainBundle().pathForResource("RemoteSettings", ofType: "plist")
    }
    
    var remoteSettings: [String: String]? {
        guard let path = remoteSettingsPath else {
            return nil
        }
        
        return NSDictionary(contentsOfFile: path) as? [String: String]
    }
    
    var bundleDisplayName: String {
        return objectForInfoDictionaryKey("CFBundleDisplayName") as! String
    }
}

