//
//  DeeplinkManager.swift
//  Loop
//
//  Created by Cameron Ingham on 6/26/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import UIKit

class DeeplinkManager {
    
    private weak var rootViewController: UIViewController?
    
    init(rootViewController: UIViewController?) {
        self.rootViewController = rootViewController
    }
    
    func handle(_ url: URL) -> Bool {
        guard let rootViewController = rootViewController as? RootNavigationController, let deeplink = Deeplink(url: url) else {
            return false
        }
        
        rootViewController.navigate(to: deeplink)
        return true
    }
    
    func handle(_ deeplink: Deeplink) -> Bool {
        guard let rootViewController = rootViewController as? RootNavigationController else {
            return false
        }
        
        rootViewController.navigate(to: deeplink)
        return true
    }
}
