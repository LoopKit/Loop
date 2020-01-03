//
//  Tuning.swift
//  Loop
//
//  Created by marius eriksen on 12/19/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

/// A TuningTimeline is a columnar representation of a data timeline, such as glucose, basal, bolus, or carbs. Each column in a TuningTimeline must be of the same length.
/// TODO: delta encoding should be a coding concern; values here should be represented directly
struct TuningTimeline: Codable {
    /// ColumnType is the type of the column. Most tuning services accept "basal", "bolus", "carbs", "glucose", or "insulin".
    var columnType: String
    /// Parameters is the set of parameters for the column. For example, insulin columns specify insulin curve parameters; carb columns include carbohydrate parameters.
    var parameters: [String: Double]
    /// Index stores the delta-encoded indices of the entries in this timeline. The index is the number of seconds since an epoch. The epoch is the Unix epoch for request timelines. When TuningTimelines are used for parameter schedules, the epoch is midnight (entries are repeating, relative to midnight in the requested timezone).
    var index: [Int]
    /// Values stores the delta-encoded values in this timeline, as indexed by the index above.
    var values: [Double]
    /// Durations is an optional column that associates durations with each entry. This may be used to represent basal insulin deliveries.
    var durations: [Int]?
    
    enum CodingKeys: String, CodingKey {
        case columnType = "type"
        case parameters
        case index
        case values
        case durations
    }
}

/// A TunedSchedule represents a parameter schedule recommended by a tuner.
/// TODO: consider reconciling TuningSchedule and TuningTimeline
struct TuningSchedule: Codable {
    init(from schedule: [RepeatingScheduleValue<Double>]) {
        var index = [Int]()
        var values = [Double]()
        index.reserveCapacity(schedule.count)
        values.reserveCapacity(schedule.count)
        
        for value in schedule {
            index.append(Int(value.startTime.minutes))
            values.append(value.value)
        }

        self.index = index
        self.values = values
    }
    
    /// The index is the number of minutes after midnight the particular parameter value should begin.
    let index: [Int]
    /// Values stores the parameter values, indexed by the timestamps above.
    let values: [Double]
    
    /// Represent this schedule as a Loop RepeatingSchedule.
    var repeatingSchedule: [RepeatingScheduleValue<Double>] {
        // XXX: figure out if this does the correct thing when
        // schedules straddle midnight.
        get {
            // TODO: this would segfault on a malformed schedule.
            return index.enumerated().map {
                RepeatingScheduleValue(startTime: TimeInterval(minutes: Double($1)), value: values[$0])
            }
        }
    }
}

// MARK: - request

/// TuningRequest encodes a request to a tuning service. It includes all data and parameters required for the tuning service create and train a model.
struct TuningRequest: Encodable {
    /// Version indicates the version of the tuning request. It is currently always 1.
    var version: Int
    
    /// Timezone is the user's timezone. This is used to deduce the "time of day" hour of the data that follows, which in turn is used to index parameter schedules.
    /// TODO: ideally, we'd have a timezone for each data point, but this does not appear to be captured currently.
    var timezone: String
    
    // TODO: add current basals, max basal, allowable basal values, etc.
    
    /// Timelines is the set of data timelines to be used as features for the tuner. They typically include basal, bolus, carb, and glucose timelines.
    var timelines: [TuningTimeline]
    
    /// The set of allowable basal rates (U/h).
    var allowedBasalRates: [Double]
    
    /// The maximum allowable number of items in the basal rate schedule.
    var maximumScheduleItemCount: Int
    
    /// The smallest time interval allowable in basal rate schedules (in seconds).
    var minimumTimeInterval: Int
    
    var basalRateSchedule: TuningSchedule?
    
    var insulinSensitivitySchedule: TuningSchedule?
    
    var carbRatioSchedule: TuningSchedule?
    
    var basalInsulinParameters: [String: Double]

    enum CodingKeys: String, CodingKey {
        case version
        case timezone
        case timelines
        case allowedBasalRates = "allowed_basal_rates"
        case maximumScheduleItemCount = "maximum_schedule_item_count"
        case minimumTimeInterval = "minimum_time_interval"
        case basalRateSchedule = "basal_rate_schedule"
        case insulinSensitivitySchedule = "insulin_sensitivity_schedule"
        case carbRatioSchedule = "carb_ratio_schedule"
        case basalInsulinParameters = "basal_insulin_parameters"
    }
}

// MARK: - response

// TODO: define errors in the protocol

/// TuningResponses are returned from tuners.
struct TuningResponse: Decodable {
    /// The version of the tuning response. Only version 1 is currently supported.
    let version: Int
    
    /// The tuned basal schedule.
    var basalRateSchedule: TuningSchedule
    /// The tuned carbohydrate ratio schedule.
    var carbRatioSchedule: TuningSchedule
    /// The tuned insulin sensitivity schedule.
    var insulinSensitivitySchedule: TuningSchedule
    
    enum CodingKeys: String, CodingKey {
        case version = "version"
        case basalRateSchedule = "basal_rate_schedule"
        case carbRatioSchedule = "carb_ratio_schedule"
        case insulinSensitivitySchedule = "insulin_sensitivity_schedule"
    }
}
