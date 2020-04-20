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
    
    func fetchEffects(for day: DateInterval, retrospectiveCorrection: RetrospectiveCorrection, delta: TimeInterval) -> Result<GlucoseEffects>
}

struct LearnTherapySettings {
    typealias RawValue = [String: Any]

    var momentumDataInterval: TimeInterval
    var insulinModel: InsulinModelSettings
    var basalSchedule: BasalRateSchedule
    var sensitivity: InsulinSensitivitySchedule
    var carbRatios: CarbRatioSchedule
    var absorptionTimeOverrun: Double
    var defaultAbsorptionTime: TimeInterval
    var carbAbsortionModel: CarbAbsorptionModel
    var carbEffectDelay: TimeInterval
    
    var carbModelSettings: CarbModelSettings {
        return carbAbsortionModel.settings(with: absorptionTimeOverrun)
    }

    init(momentumDataInterval: TimeInterval,
         insulinModel: InsulinModelSettings,
         basalSchedule: BasalRateSchedule,
         sensitivity: InsulinSensitivitySchedule,
         carbRatios: CarbRatioSchedule,
         absorptionTimeOverrun: Double,
         defaultAbsorptionTime: TimeInterval,
         carbAbsortionModel: CarbAbsorptionModel,
         carbEffectDelay: TimeInterval)
    {
        self.momentumDataInterval = momentumDataInterval
        self.insulinModel = insulinModel
        self.basalSchedule = basalSchedule
        self.sensitivity = sensitivity
        self.carbRatios = carbRatios
        self.absorptionTimeOverrun = absorptionTimeOverrun
        self.defaultAbsorptionTime = defaultAbsorptionTime
        self.carbAbsortionModel = carbAbsortionModel
        self.carbEffectDelay = carbEffectDelay
    }
    
    init?(rawValue: RawValue) {
        guard
            let momentumDataInterval = rawValue["momentumDataInterval"] as? TimeInterval,
            let insulinModelRaw = rawValue["insulinModel"] as? InsulinModelSettings.RawValue,
            let insulinModel = InsulinModelSettings(rawValue: insulinModelRaw),
            let basalScheduleRaw = rawValue["basalSchedule"] as? BasalRateSchedule.RawValue,
            let basalSchedule = BasalRateSchedule(rawValue: basalScheduleRaw),
            let sensitivityRaw = rawValue["sensitivity"] as? InsulinSensitivitySchedule.RawValue,
            let sensitivity = InsulinSensitivitySchedule(rawValue: sensitivityRaw),
            let carbRatiosRaw = rawValue["carbRatios"] as? CarbRatioSchedule.RawValue,
            let carbRatios = CarbRatioSchedule(rawValue: carbRatiosRaw),
            let absorptionTimeOverrun = rawValue["absorptionTimeOverrun"] as? Double,
            let defaultAbsorptionTime = rawValue["defaultAbsorptionTime"] as? TimeInterval,
            let carbAbsortionModelRaw = rawValue["carbAbsortionModel"] as? CarbAbsorptionModel.RawValue,
            let carbAbsorptionModel = CarbAbsorptionModel(rawValue: carbAbsortionModelRaw),
            let carbEffectDelay = rawValue["carbEffectDelay"] as? TimeInterval
        else {
            return nil
        }
        self.momentumDataInterval = momentumDataInterval
        self.insulinModel = insulinModel
        self.basalSchedule = basalSchedule
        self.sensitivity = sensitivity
        self.carbRatios = carbRatios
        self.absorptionTimeOverrun = absorptionTimeOverrun
        self.defaultAbsorptionTime = defaultAbsorptionTime
        self.carbAbsortionModel = carbAbsorptionModel
        self.carbEffectDelay = carbEffectDelay
    }
    
    var rawValue: RawValue {
        return [
            "momentumDataInterval": momentumDataInterval,
            "insulinModel": insulinModel.rawValue,
            "basalSchedule": basalSchedule.rawValue,
            "sensitivity": sensitivity.rawValue,
            "carbRatios": carbRatios.rawValue,
            "absorptionTimeOverrun": absorptionTimeOverrun,
            "defaultAbsorptionTime": defaultAbsorptionTime,
            "carbAbsortionModel": carbAbsortionModel.rawValue,
            "carbEffectDelay": carbEffectDelay
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
