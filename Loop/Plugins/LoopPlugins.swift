//
//  LoopPlugins.swift
//  Loop
//
//  Created by Pete Schwamb on 7/24/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import LoopKitUI

typealias AvailableService = AvailableDevice

class PluginManager {
    private let pluginBundles: [Bundle]

    public init(pluginsURL: URL? = Bundle.main.privateFrameworksURL) {
        var bundles = [Bundle]()

        if let pluginsURL = pluginsURL {
            do {
                for pluginURL in try FileManager.default.contentsOfDirectory(at: pluginsURL, includingPropertiesForKeys: nil).filter{$0.path.hasSuffix(".framework")} {
                    if let bundle = Bundle(url: pluginURL), bundle.isLoopPlugin {
                        print("Found loop plugin at \(pluginURL)")
                        bundles.append(bundle)
                    }
                }
            } catch let error {
                print("Error loading plugins: \(String(describing: error))")
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
                    print(error)
                }
            }
        }
        return nil
    }

    var availablePumpManagers: [AvailableDevice] {
        return pluginBundles.compactMap({ (bundle) -> AvailableDevice? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerDisplayName.rawValue) as? String,
                let identifier = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String else {
                    return nil
            }

            return AvailableDevice(identifier: identifier, localizedTitle: title)
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
                    print(error)
                }
            }
        }
        return nil
    }
    
    var availableCGMManagers: [AvailableDevice] {
        return pluginBundles.compactMap({ (bundle) -> AvailableDevice? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerDisplayName.rawValue) as? String,
                let identifier = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String else {
                    return nil
            }
            
            return AvailableDevice(identifier: identifier, localizedTitle: title)
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
                    print(error)
                }
            }
        }
        return nil
    }

    var availableServices: [AvailableService] {
        return pluginBundles.compactMap({ (bundle) -> AvailableService? in
            guard let title = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.serviceDisplayName.rawValue) as? String,
                let identifier = bundle.object(forInfoDictionaryKey: LoopPluginBundleKey.serviceIdentifier.rawValue) as? String else {
                    return nil
            }

            return AvailableService(identifier: identifier, localizedTitle: title)
        })
    }

}


extension Bundle {
    var isLoopPlugin: Bool {
        return
            object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String != nil ||
            object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String != nil ||
            object(forInfoDictionaryKey: LoopPluginBundleKey.serviceIdentifier.rawValue) as? String != nil
    }
}
