//
//  ContextInterfaceController.swift
//  Loop
//
//  Created by Nathan Racklyeft on 5/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import WatchKit
import Foundation


class ContextInterfaceController: WKInterfaceController {

    let dataManager = DeviceDataManager.sharedManager

    private var lastContextDataObserverContext = 0

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        // Configure interface objects here.
    }

    override func willActivate() {
        super.willActivate()

        dataManager.addObserver(self, forKeyPath: "lastContextData", options: [], context: &lastContextDataObserverContext)

        updateFromContext(dataManager.lastContextData)
    }

    override func didDeactivate() {
        super.didDeactivate()

        dataManager.removeObserver(self, forKeyPath: "lastContextData", context: &lastContextDataObserverContext)

    }

    func updateFromContext(_ context: WatchContext?) {
        DeviceDataManager.sharedManager.updateComplicationDataIfNeeded()
    }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == &lastContextDataObserverContext {
            if let context = dataManager.lastContextData {
                updateFromContext(context)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

}
