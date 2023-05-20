//
//  PluginManager.swift
//  Loop
//
//  Created by Pete Schwamb on 7/24/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import os.log
import Foundation
import LoopKit
import LoopKitUI

class PluginManager {
    let pluginBundles: [Bundle]

    private let log = OSLog(category: "PluginManager")

    public init(pluginsURL: URL? = Bundle.main.privateFrameworksURL) {
        var bundles = [Bundle]()

        if let pluginsURL = pluginsURL {
            do {
                for pluginURL in try FileManager.default.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil).filter({$0.path.hasSuffix(".framework")}) {
                    if let bundle = Bundle(url: pluginURL) {
                        if bundle.isLoopPlugin && (!bundle.isSimulator || FeatureFlags.allowSimulators) {
                            log.debug("Found loop plugin: %{public}@", pluginURL.absoluteString)
                            bundles.append(bundle)
                        }
                    }
                }
            } catch let error {
                log.error("Error loading plugins: %{public}@", String(describing: error))
            }
        }
        self.pluginBundles = bundles
    }

    

    func getPumpManagerTypeByIdentifier(_ identifier: String) -> PumpManagerUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String, name == identifier {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {

                        if let plugin = principalClass.init() as? PumpManagerUIPlugin {
                            return plugin.pumpManagerType
                        } else {
                            fatalError("PrincipalClass does not conform to PumpManagerUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch let error {
                    log.error("Error loading plugin: %{public}@", String(describing: error))
                }
            }
        }
        return nil
    }

    var availablePumpManagers: [PumpManagerDescriptor] {
        return pluginBundles.compactMap({ (bundle) -> PumpManagerDescriptor? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerDisplayName.rawValue) as? String,
                let identifier = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String else {
                    return nil
            }
            
            return PumpManagerDescriptor(identifier: identifier, localizedTitle: title)
        })
    }
    
    func getCGMManagerTypeByIdentifier(_ identifier: String) -> CGMManagerUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String, name == identifier {
                do {
                    try bundle.loadAndReturnError()
                    
                    if let principalClass = bundle.principalClass as? NSObject.Type {
                        
                        if let plugin = principalClass.init() as? CGMManagerUIPlugin {
                            return plugin.cgmManagerType
                        } else {
                            fatalError("PrincipalClass does not conform to CGMManagerUIPlugin")
                        }
                        
                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch let error {
                    log.error("Error loading plugin: %{public}@", String(describing: error))
                }
            }
        }
        return nil
    }
    
    var availableCGMManagers: [CGMManagerDescriptor] {
        return pluginBundles.compactMap({ (bundle) -> CGMManagerDescriptor? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerDisplayName.rawValue) as? String,
                let identifier = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String else {
                    return nil
            }
            
            return CGMManagerDescriptor(identifier: identifier, localizedTitle: title)
        })
    }

    func getServiceTypeByIdentifier(_ identifier: String) -> ServiceUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.serviceIdentifier.rawValue) as? String, name == identifier {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {

                        if let plugin = principalClass.init() as? ServiceUIPlugin {
                            return plugin.serviceType
                        } else {
                            fatalError("PrincipalClass does not conform to ServiceUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch let error {
                    log.error("Error loading plugin: %{public}@", String(describing: error))
                }
            }
        }
        return nil
    }

    var availableServices: [ServiceDescriptor] {
        return pluginBundles.compactMap({ (bundle) -> ServiceDescriptor? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.serviceDisplayName.rawValue) as? String,
                let identifier = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.serviceIdentifier.rawValue) as? String else {
                    return nil
            }

            return ServiceDescriptor(identifier: identifier, localizedTitle: title)
        })
    }

    func getOnboardingTypeByIdentifier(_ identifier: String) -> OnboardingUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.onboardingIdentifier.rawValue) as? String, name == identifier {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {

                        if let plugin = principalClass.init() as? OnboardingUIPlugin {
                            return plugin.onboardingType
                        } else {
                            fatalError("PrincipalClass does not conform to OnboardingUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch let error {
                    log.error("Error loading plugin: %{public}@", String(describing: error))
                }
            }
        }
        return nil
    }

    var availableOnboardingIdentifiers: [String] {
        return pluginBundles.compactMap({ (bundle) -> String? in
            return bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.onboardingIdentifier.rawValue) as? String
        })
    }

    func getSupportUITypeByIdentifier(_ identifier: String) -> SupportUI.Type? {
        for bundle in pluginBundles {
            if let name = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.supportIdentifier.rawValue) as? String, name == identifier {
                do {
                    try bundle.loadAndReturnError()

                    if let principalClass = bundle.principalClass as? NSObject.Type {

                        if let plugin = principalClass.init() as? SupportUIPlugin {
                            return type(of: plugin.support)
                        } else {
                            fatalError("PrincipalClass does not conform to SupportUIPlugin")
                        }

                    } else {
                        fatalError("PrincipalClass not found")
                    }
                } catch let error {
                    log.error("Error loading plugin: %{public}@", String(describing: error))
                }
            }
        }
        return nil
    }

}


extension Bundle {
    var isPumpManagerPlugin: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String != nil }
    var isCGMManagerPlugin: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String != nil }
    var isServicePlugin: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.serviceIdentifier.rawValue) as? String != nil }
    var isOnboardingPlugin: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.onboardingIdentifier.rawValue) as? String != nil }
    var isSupportPlugin: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.supportIdentifier.rawValue) as? String != nil }

    var isLoopPlugin: Bool { isPumpManagerPlugin || isCGMManagerPlugin || isServicePlugin || isOnboardingPlugin || isSupportPlugin }

    var isLoopExtension: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.extensionIdentifier.rawValue) as? String != nil }

    var isSimulator: Bool { object(forInfoDictionaryKey: LoopPluginBundleKey.pluginIsSimulator.rawValue) as? Bool == true }
}
