//
//  PluginManager.swift
//  Loop
//
//  Created by Pete Schwamb on 7/24/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI


public struct AvailableDevice {
    public let identifier: String
    public let localizedTitle: String
    public let providesOnboarding: Bool
    
    public init(identifier: String, localizedTitle: String, providesOnboarding: Bool) {
        self.identifier = identifier
        self.localizedTitle = localizedTitle
        self.providesOnboarding = providesOnboarding
    }
}

public typealias AvailableService = AvailableDevice

public class PluginManager {

    public init(pluginsURL: URL? = Bundle.main.privateFrameworksURL) {
    }

    public func getPumpManagerTypeByIdentifier(_ identifier: String) -> PumpManagerUI.Type? {
        return Plugins.pumpManagers.first { identifier == $0.managerIdentifier }
    }

    public var availablePumpManagers: [AvailableDevice] {
        return Plugins.pumpManagers.map {
            AvailableDevice(identifier: $0.managerIdentifier, localizedTitle: $0.localizedTitle, providesOnboarding: false)
        }
    }
    
    public func getCGMManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type? {
        return nil
    }
    
    public var availableCGMManagers: [AvailableDevice] {
        return []
    }

    public func getServiceTypeByIdentifier(_ identifier: String) -> ServiceUI.Type? {
        return nil
    }

    public var availableServices: [AvailableService] {
        return []
    }

}
