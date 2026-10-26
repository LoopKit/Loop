//
//  DeeplinkManager.swift
//  Loop
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import UIKit

enum Deeplink: String, CaseIterable {
    case carbEntry = "carb-entry"
    case bolus = "manual-bolus"
    case preMeal = "pre-meal-preset"
    case customPresets = "custom-presets"
    
    init?(url: URL?) {
        guard let url, let host = url.host, let deeplink = Deeplink.allCases.first(where: { $0.rawValue == host }) else {
            return nil
        }
        
        self = deeplink
    }
}

class DeeplinkManager {
    
    /// The window's root changes when the interface is switched, so it is looked up on each link.
    private let rootViewController: () -> UIViewController?
    
    init(rootViewController: @escaping () -> UIViewController?) {
        self.rootViewController = rootViewController
    }
    
    func handle(_ url: URL) -> Bool {
        guard let deeplink = Deeplink(url: url) else {
            return false
        }
        
        return handle(deeplink)
    }
    
    func handle(_ deeplink: Deeplink) -> Bool {
        guard let root = rootViewController(), let rootNavigationController = root.loopRootNavigationController else {
            return false
        }
        
        (root as? MainTabBarController)?.showNow()
        rootNavigationController.navigate(to: deeplink)
        return true
    }
}
