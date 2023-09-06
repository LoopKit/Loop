//
//  SecuritiesManager.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2023-09-06.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import LoopCore
import Combine

class SecuritiesManager {

    private let pluginManager: PluginManager
    
    private let servicesManager: ServicesManager
    
    private var securities = [Security]()

    private let securitiesLock = UnfairLock()

    init(pluginManager: PluginManager,
         servicesManager: ServicesManager)
    {
        self.pluginManager = pluginManager
        self.servicesManager = servicesManager
    }

    public var availableSecurityIdentifiers: [String] {
        return pluginManager.availableSecurityIdentifiers
    }

    func setupSecurity(withIdentifier identifier: String) -> Security? {
        for security in securities {
            if security.identifier == identifier {
                return security
            }
        }
        
        guard let security = pluginManager.getSecurityByIdentifier(identifier) else { return nil }
        security.initializationComplete(for: servicesManager.activeServices)
        addActiveSecurity(security)
        return security
    }

    public func addActiveSecurity(_ security: Security) {
        securitiesLock.withLock {
            securities.append(security)
        }
    }

    public func removeActiveSecurity(_ security: Security) {
        securitiesLock.withLock {
            securities.removeAll { $0.identifier == security.identifier }
        }
    }
}
