//
//  RemoteDataManager.swift
//  Learn
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import LoopCore
import LoopKit
import LoopUI
import HealthKit

protocol LearnDataSource {
    var title: String { get }

    var identifier: String { get }
    
    var category: String { get }
    
    func fetchEffects(for day: DateInterval, retrospectiveCorrection: RetrospectiveCorrection, momentumDataInterval: TimeInterval) -> Result<GlucoseEffects>
}

struct LearnTherapySettings {
    typealias RawValue = [String: Any]

    var momentumDataInterval: TimeInterval
    var insulinModel: InsulinModelSettings
    
    init(momentumDataInterval: TimeInterval, insulinModel: InsulinModelSettings) {
        self.momentumDataInterval = momentumDataInterval
        self.insulinModel = insulinModel
    }
    
    init?(rawValue: RawValue) {
        guard
            let momentumDataInterval = rawValue["momentumDataInterval"] as? TimeInterval,
            let insulinModelRaw = rawValue["insulinModel"] as? InsulinModelSettings.RawValue,
            let insulinModel = InsulinModelSettings(rawValue: insulinModelRaw)
        else {
            return nil
        }
        self.momentumDataInterval = momentumDataInterval
        self.insulinModel = insulinModel
    }
    
    var rawValue: RawValue {
        return [
            "momentumDataInterval": momentumDataInterval,
            "insulinModel": insulinModel.rawValue,
        ]
    }
}




class DataSourceManager {
    
    private var nightscoutDataSources: [NightscoutDataSource] {
        didSet {
            UserDefaults.appGroup?.nightscoutDataSourcesRawValue = nightscoutDataSources.map { $0.rawState }
        }
    }
    
    var dataSources: [LearnDataSource] {
        let dataSources: [LearnDataSource?] = [localLoopDataSource] + nightscoutDataSources
        return dataSources.compactMap { $0 }
    }
    
    var localLoopDataSource: LearnDataSource? {
        didSet {
            if selectedDataSource == nil {
                self.selectedDataSource = localLoopDataSource
            }
        }
    }
    
    var selectedDataSource: LearnDataSource? {
        didSet {
            UserDefaults.appGroup?.selectedDataSource = selectedDataSource?.identifier
        }
    }
    
    init() {
        if let raw = UserDefaults.appGroup?.nightscoutDataSourcesRawValue {
            nightscoutDataSources = raw.compactMap { NightscoutDataSource(rawState: $0) }
        } else {
            nightscoutDataSources = []
        }
        
        let initialDataSources: [LearnDataSource] = ([localLoopDataSource] + nightscoutDataSources).compactMap { $0 }
        
        if let selectedDataSourceIdentifier = UserDefaults.appGroup?.selectedDataSource,
            let selectedDataSource = initialDataSources.first(where: { $0.identifier == selectedDataSourceIdentifier })
        {
            self.selectedDataSource = selectedDataSource
        }
    }
    
    func addNightscoutDataSource(_ source: NightscoutDataSource) {
        nightscoutDataSources.append(source)
    }
}

extension GlucoseEntry {
    var asStoredGlucoseSample: StoredGlucoseSample? {
        
        guard let uuid = identifier.asUUID else {
            return nil
        }
        
        return StoredGlucoseSample(
            sampleUUID: uuid,
            syncIdentifier: identifier,
            syncVersion: 0,
            startDate: date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: sgv),
            isDisplayOnly: false,
            provenanceIdentifier: device)
    }
}

extension String {
    var asUUID: UUID? {
        guard let data = padding(toLength: 32, withPad: " ", startingAt: 0).data(using: .utf8) else {
            return nil
        }
        return data.withUnsafeBytes { $0.load(as: UUID.self) }
    }
}

extension UserDefaults {
    private enum Key: String {
        case nightscoutDataSources = "com.loopkit.Learn.NightScoutDataSources"
        case selectedDataSource = "com.loopkit.Learn.SelectedDataSource"
    }

    var nightscoutDataSourcesRawValue: [NightscoutDataSource.RawStateValue]? {
        get {
            return array(forKey: Key.nightscoutDataSources.rawValue) as? [NightscoutDataSource.RawStateValue]
        }
        set {
            set(newValue, forKey: Key.nightscoutDataSources.rawValue)
        }
    }
    
    var selectedDataSource: String? {
        get {
            return string(forKey: Key.selectedDataSource.rawValue)
        }
        set {
            set(newValue, forKey: Key.selectedDataSource.rawValue)
        }
    }
}
