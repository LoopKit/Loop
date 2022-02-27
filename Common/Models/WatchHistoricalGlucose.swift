//
//  WatchHistoricalGlucose.swift
//  Loop
//
//  Created by Bharat Mediratta on 6/22/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

struct WatchHistoricalGlucose {
    let samples: [StoredGlucoseSample]
}

extension WatchHistoricalGlucose: RawRepresentable {
    typealias RawValue = [String: Any]

    init?(rawValue: RawValue) {
        guard let rawSamples = rawValue["samples"] as? Data,
            let flattened = try? Self.decoder.decode(Flattened.self, from: rawSamples) else {
                return nil
        }
        self.samples = flattened.samples
    }

    var rawValue: RawValue {
        guard let rawSamples = try? Self.encoder.encode(Flattened(samples: samples)) else {
            return [:]
        }
        return [
            "samples": rawSamples
        ]
    }

    private struct Flattened: Codable {
        let uuids: [UUID?]
        let provenanceIdentifiers: [String]
        let syncIdentifiers: [String?]
        let syncVersions: [Int?]
        let startDates: [Date]
        let quantities: [Double]
        let conditions: [GlucoseCondition?]
        let trends: [GlucoseTrend?]
        let trendRates: [Double?]
        let isDisplayOnlys: [Bool]
        let wasUserEntereds: [Bool]
        let devices: [Data?]
        let healthKitEligibleDates: [Date?]

        init(samples: [StoredGlucoseSample]) {
            self.uuids = samples.map { $0.uuid }
            self.provenanceIdentifiers = samples.map { $0.provenanceIdentifier }
            self.syncIdentifiers = samples.map { $0.syncIdentifier }
            self.syncVersions = samples.map { $0.syncVersion }
            self.startDates = samples.map { $0.startDate }
            self.quantities = samples.map { $0.quantity.doubleValue(for: .milligramsPerDeciliter) }
            self.conditions = samples.map { $0.condition }
            self.trends = samples.map { $0.trend }
            self.trendRates = samples.map { $0.trendRate.flatMap { $0.doubleValue(for: .milligramsPerDeciliterPerMinute) } }
            self.isDisplayOnlys = samples.map { $0.isDisplayOnly }
            self.wasUserEntereds = samples.map { $0.wasUserEntered }
            self.devices = samples.map { try? WatchHistoricalGlucose.encoder.encode($0.device) }
            self.healthKitEligibleDates = samples.map { $0.healthKitEligibleDate }
        }

        var samples: [StoredGlucoseSample] {
            return (0..<uuids.count).map {
                return StoredGlucoseSample(uuid: uuids[$0],
                                           provenanceIdentifier: provenanceIdentifiers[$0],
                                           syncIdentifier: syncIdentifiers[$0],
                                           syncVersion: syncVersions[$0],
                                           startDate: startDates[$0],
                                           quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: quantities[$0]),
                                           condition: conditions[$0],
                                           trend: trends[$0],
                                           trendRate: trendRates[$0].flatMap { HKQuantity(unit: .milligramsPerDeciliterPerMinute, doubleValue: $0) },
                                           isDisplayOnly: isDisplayOnlys[$0],
                                           wasUserEntered: wasUserEntereds[$0],
                                           device: devices[$0].flatMap { try? HKDevice(from: $0) },
                                           healthKitEligibleDate: healthKitEligibleDates[$0])
            }
        }
    }

    fileprivate static var encoder: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }

    fileprivate static var decoder: PropertyListDecoder = PropertyListDecoder()
}
