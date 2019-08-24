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

                        if let plugin = principalClass.init() as? LoopUIPlugin {
                            return plugin.pumpManagerType
                        } else {
                            fatalError("PrincipalClass does not conform to LoopUIPlugin")
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
}


extension Bundle {
    var isLoopPlugin: Bool {
        return
            object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) as? String != nil ||
            object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) as? String != nil
    }
}
