//
//  NightscoutDataSource.swift
//  Learn
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import LoopKit
import LoopUI
import LoopCore

class NightscoutDataSource: LearnDataSource {

    typealias RawStateValue = [String: Any]
    
    var category: String {
        return "Nightscout"
    }

    var title: String
    
    var identifier: String
    
    var therapySettings: LearnTherapySettings
    
    var api: NightscoutUploader

    init?(rawState: RawStateValue) {
        guard
            let title = rawState["title"] as? String,
            let identifier = rawState["identifier"] as? String,
            let settingsRaw = rawState["settings"] as? LearnTherapySettings.RawValue,
            let settings = LearnTherapySettings(rawValue: settingsRaw)
        else {
            return nil
        }
        
        self.title = title
        self.identifier = identifier
        self.therapySettings = settings
        
        let keychain = KeychainManager()
        
        if let (siteURL, APISecret) = keychain.getNightscoutCredentials(identifier: identifier) {
            self.api = NightscoutUploader(siteURL: siteURL, APISecret: APISecret)
        } else {
            return nil
        }
    }

    var rawState: RawStateValue {
        return [
            "title": title,
            "identifier": identifier,
            "settings": therapySettings.rawValue
        ]
    }
    
    init(title: String, identifier: String, api: NightscoutUploader, therapySettings: LearnTherapySettings) {
        self.title = title
        self.identifier = identifier
        self.therapySettings = therapySettings
        self.api = api
    }
    
    func fetchEffects(for day: DateInterval, retrospectiveCorrection: RetrospectiveCorrection, momentumDataInterval: TimeInterval) -> Result<GlucoseEffects> {

        let fetchGroup = DispatchGroup()
        
        var glucose: [StoredGlucoseSample]? = []
//        var insulinEffects: [GlucoseEffect]?
//        var counteractionEffects: [GlucoseEffectVelocity]?
//        var carbEffects: [GlucoseEffect]?
//        var retrospectiveGlucoseDiscrepanciesSummed: [GlucoseChange]?
        
        let forecastDuration = therapySettings.insulinModel.model.effectDuration

        fetchGroup.enter()
        let neededGlucoseInterval = DateInterval(start: day.start.addingTimeInterval(-therapySettings.momentumDataInterval),
                                                 end: day.end.addingTimeInterval(forecastDuration))
        api.fetchGlucose(dateInterval: neededGlucoseInterval, maxCount: 600) { (result) in
            switch result {
            case .failure(let error):
                print("Error fetching glucose: \(error)")
            case .success(let samples):
                print("Fetched \(samples.count) glucose samples")
                glucose = samples.compactMap { $0.asStoredGlucoseSample }
            }
            fetchGroup.leave()
        }
        
        fetchGroup.enter()
        api.fetchTreatments(dateInterval: day, maxCount: 500) { (result) in
            switch result {
            case .failure(let error):
                print("Error fetching glucose: \(error)")
            case .success(let treatments):
                print("Fetched \(treatments.count) treatments")
            }
            fetchGroup.leave()
        }
        
        _ = fetchGroup.wait(timeout: .now() + .seconds(10))
        
        let glucoseEffects = GlucoseEffects(dateInterval: day, glucose: glucose!, insulinEffects: [], counteractionEffects: [], carbEffects: [], retrospectiveGlucoseDiscrepanciesSummed: [])
        
        return .success(glucoseEffects)
    }
}

