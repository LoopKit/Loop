//
//  WatchPluginManager.swift
//  WatchApp Extension
//
//  The device kits the watch app carries but does not link, loaded at run time as the phone's
//  PluginManager loads its plugins: found by the identifier in each bundle's Info.plist, and loaded
//  when that identifier is first asked for. The watch has no LoopKitUI, so a kit's own framework is
//  its plugin; its principal class is a LoopKit `PumpManagerPlugin` or `CGMManagerPlugin`.
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import os.log

final class WatchPluginManager {
    static let shared = WatchPluginManager()

    let pluginBundles: [Bundle]

    private let log = OSLog(category: "WatchPluginManager")

    /// Each plugin's principal class, instantiated once, by identifier.
    private let loaded = Locked<[String: NSObject]>([:])

    init(pluginsURL: URL? = Bundle.main.privateFrameworksURL) {
        let urls = pluginsURL.flatMap { try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) } ?? []
        pluginBundles = urls.filter { $0.pathExtension == "framework" }.compactMap(Bundle.init(url:)).filter {
            $0.object(forInfoDictionaryKey: LoopPluginBundleKey.pumpManagerIdentifier.rawValue) is String ||
            $0.object(forInfoDictionaryKey: LoopPluginBundleKey.cgmManagerIdentifier.rawValue) is String
        }
    }

    func pumpManagerType(withIdentifier identifier: String) -> PumpManager.Type? {
        (plugin(forKey: .pumpManagerIdentifier, identifier) as? PumpManagerPlugin)?.pumpManagerType
    }

    func cgmManagerType(withIdentifier identifier: String) -> CGMManager.Type? {
        (plugin(forKey: .cgmManagerIdentifier, identifier) as? CGMManagerPlugin)?.cgmManagerType
    }

    private func plugin(forKey key: LoopPluginBundleKey, _ identifier: String) -> NSObject? {
        if let plugin = loaded.value[identifier] {
            return plugin
        }
        guard let bundle = pluginBundles.first(where: { $0.object(forInfoDictionaryKey: key.rawValue) as? String == identifier }) else {
            return nil
        }
        do {
            try bundle.loadAndReturnError()
        } catch {
            log.error("Error loading plugin %{public}@: %{public}@", identifier, String(describing: error))
            return nil
        }
        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            log.error("Plugin %{public}@ has no principal class", identifier)
            return nil
        }
        log.default("Loaded plugin %{public}@", identifier)
        let plugin = principalClass.init()
        loaded.mutate { $0[identifier] = plugin }
        return plugin
    }
}
