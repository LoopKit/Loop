//
//  StatefulPluginManager.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2023-09-06.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import LoopKit
import LoopKitUI
import LoopCore
import Combine

class StatefulPluginManager: StatefulPluggableProvider {

    private let pluginManager: PluginManager
    
    private let servicesManager: ServicesManager
    
    private var statefulPlugins = [StatefulPluggable]()

    private let statefulPluginLock = UnfairLock()

    @PersistedProperty(key: "StatefulPlugins")
    var rawStatefulPlugins: [StatefulPluggable.RawStateValue]?
    
    init(pluginManager: PluginManager,
         servicesManager: ServicesManager)
    {
        self.pluginManager = pluginManager
        self.servicesManager = servicesManager
        restoreState()
    }

    public var availableStatefulPluginIdentifiers: [String] {
        return pluginManager.availableStatefulPluginIdentifiers
    }

    func statefulPlugin(withIdentifier identifier: String) -> StatefulPluggable? {
        for plugin in statefulPlugins {
            if plugin.pluginIdentifier == identifier {
                return plugin
            }
        }
        
        return setupStatefulPlugin(withIdentifier: identifier)
    }
    
    func statefulPluginType(withIdentifier identifier: String) -> StatefulPluggable.Type? {
        pluginManager.getStatefulPluginTypeByIdentifier(identifier)
    }

    func setupStatefulPlugin(withIdentifier identifier: String) -> StatefulPluggable? {
        guard let statefulPluinType = pluginManager.getStatefulPluginTypeByIdentifier(identifier) else { return nil }
        
        // init without raw value
        let statefulPlugin = statefulPluinType.init(rawState: [:])
        statefulPlugin?.initializationComplete(for: servicesManager.activeServices)
        addActiveStatefulPlugin(statefulPlugin)
        
        return statefulPlugin
    }
        
    private func statefulPluginTypeFromRawValue(_ rawValue: StatefulPluggable.RawStateValue) -> StatefulPluggable.Type? {
        guard let identifier = rawValue["statefulPluginIdentifier"] as? String else {
            return nil
        }

        return statefulPluginType(withIdentifier: identifier)
    }
    
    private func statefulPluginFromRawValue(_ rawValue: StatefulPluggable.RawStateValue) -> StatefulPluggable? {
        guard let statefulPluginType = statefulPluginTypeFromRawValue(rawValue),
            let rawState = rawValue["state"] as? StatefulPluggable.RawStateValue
        else {
            return nil
        }

        return statefulPluginType.init(rawState: rawState)
    }
    
    public var activeStatefulPlugins: [StatefulPluggable] {
        return statefulPluginLock.withLock { statefulPlugins }
    }

    public func addActiveStatefulPlugin(_ statefulPlugin: StatefulPluggable?) {
        guard let statefulPlugin = statefulPlugin else { return }
        statefulPluginLock.withLock {
            statefulPlugin.stateDelegate = self
            statefulPlugins.append(statefulPlugin)
            saveState()
        }
    }

    public func removeActiveStatefulPlugin(_ statefulPlugin: StatefulPluggable) {
        statefulPluginLock.withLock {
            statefulPlugins.removeAll { $0.pluginIdentifier == statefulPlugin.pluginIdentifier }
            saveState()
        }
    }
    
    private func saveState() {
        rawStatefulPlugins = statefulPlugins.compactMap { $0.rawValue }
    }
    
    private func restoreState() {
        let rawStatefulPlugins = rawStatefulPlugins ?? []
        rawStatefulPlugins.forEach { rawValue in
            if let statefulPlugin = statefulPluginFromRawValue(rawValue) {
                statefulPlugin.initializationComplete(for: servicesManager.activeServices)
                statefulPlugins.append(statefulPlugin)
            }
        }
    }
}

extension StatefulPluginManager: StatefulPluggableDelegate {
    func pluginDidUpdateState(_ plugin: StatefulPluggable) {
        saveState()
    }
    
    func pluginWantsDeletion(_ plugin: LoopKit.StatefulPluggable) {
        removeActiveStatefulPlugin(plugin)
    }
}
