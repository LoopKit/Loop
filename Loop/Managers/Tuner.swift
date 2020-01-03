//
//  Tuner.swift
//  Loop
//
//  Created by marius eriksen on 12/22/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import HealthKit

/// Errors that can occur during tuning.
enum TunerError: Error {
    /// If the data provided were unsufficient to perform tuning.
    case insufficientData
    /// An other, underlying error occured.
    case other(_ error: Error)
    case networkError
    case serviceError(code: Int, body: String)
}

/// TunerResult is the result of a tuning operation.
enum TunerResult {
    /// Tuning succeeded with the resulting parameter schedules.
    case success(_ basalRateSchedule: BasalRateSchedule, _ carbRatioSchedule: CarbRatioSchedule, _ insulinSensitivitySchedule: InsulinSensitivitySchedule)
    /// Tuning failed with the provided error.
    case failure(_ error: TunerError)
}

struct TunerInsulinModel {
    let delay: TimeInterval
    let peak: TimeInterval
    let duration: TimeInterval

    var parameters: [String: Double] {
        get {
            return [
                "delay": delay.minutes,
                "peak": peak.minutes,
                "duration": duration.minutes,
            ]
        }
    }

    static var defaultModel = TunerInsulinModel(
        delay: .minutes(5),
        peak: .minutes(65),
        duration: .minutes(205))
}

/// Tuner is implemented by a parameter tuning system.
protocol Tuner {
    var smallestRequiredDataInterval: TimeInterval { get }
    
    /// Estimate controller parameters using the provided input data.
    /// - Parameters:
    ///   - glucoseEntries: All known glucose readings within the modeled time interval. Gaps in glucose readings are assumed to be missing readings.
    ///   - carbEntries: All known carbohydrate events within the modeled time interval. It is assumed that these entries are complete: gaps are taken to be zero.
    ///   - insulinEntries: All known insulin delivery events within the modeled time interval. It is assumed that these entries are complete: gaps represent no delivery.
    ///   - insulinModel: The insulin model used for the aforementioned insulin deliveries.
    ///   - allowedBasalRates: The set of allowable basal rates in the returned basal rate schedule.
    ///   - maximumScheduleItemCount: The maximum number of items in the returned basal rate schedule.
    ///   - minimumTimeInterval: The smallest basal rate schedule interval.
    ///   - timeZone: The timezone for which this
    ///   - basalRateSchedule: The user's current basal rate schedule, if any.
    ///   - insulinSensitivitySchedule: The user's insulin sensitivity schedule, if any.
    ///   - carbRatioSchedule: The user's carb ratio schedule, if any.
    ///   - completion: Callback for estimation result.
    /// TODO: the parameter list is a bit unwieldy; consider using a struct.
    /// TODO: relax assumptions about insulin deliveries.
    /// TODO: ideally, we'd track timezones as well, so that models are robust against large timezone changes. this will require extra tracking by Loop, perhaps by assigning timezones as healthkit metadata.
    func estimateParameters(_ glucoseEntries: [StoredGlucoseSample], _ carbEntries: [StoredCarbEntry], _ insulinEntries: [DoseEntry], _ insulinModel: TunerInsulinModel?, _ allowedBasalRates: [Double], _ maximumScheduleItemCount: Int, _ minimumTimeInterval: TimeInterval, _ timeZone: TimeZone, _ basalRateSchedule: BasalRateSchedule?, _ insulinSensitivitySchedule: InsulinSensitivitySchedule?, _ carbRatioSchedule: CarbRatioSchedule?, completion: @escaping (TunerResult) -> Void)
}

/// A tuner that calls a remote tuning service (protocol details are available at https://github.com/mariusae/tune/blob/master/README.md).
struct RemoteTuner: Tuner {
    let smallestRequiredDataInterval: TimeInterval
    /// The URL of the tuner service.
    let url: URL
   
    // MARK: - Tuner

    public func estimateParameters(_ glucoseEntries: [StoredGlucoseSample], _ carbEntries: [StoredCarbEntry], _ insulinEntries: [DoseEntry], _ insulinModel: TunerInsulinModel?, _ allowedBasalRates: [Double], _ maximumScheduleItemCount: Int, _ minimumTimeInterval: TimeInterval, _ timeZone: TimeZone, _ basalRateSchedule: BasalRateSchedule?, _ insulinSensitivitySchedule: InsulinSensitivitySchedule?, _ carbRatioSchedule: CarbRatioSchedule?, completion: @escaping (TunerResult) -> Void) {
        let glucoseTimeline = encodeTimeline(columnType: "glucose", parameters: [:], unit: .milligramsPerDeciliter, samples: glucoseEntries)
        
        let insulinParameters = (insulinModel ?? TunerInsulinModel.defaultModel).parameters
        
        // We split doses into basals and boluses so that we can attribute durations to the basal entries.
        // Some models may also want to account for basals explicitly.
        let insulinTimelines: [TuningTimeline] = Dictionary(grouping: insulinEntries, by: { $0.type }).compactMap { (type, entries) in
            switch type {
            case .resume, .suspend:
                // TODO: check temp resume.
                return nil
            case .bolus:
                let samples = entries.map({ DoseSampleValue(entry: $0) })
                return encodeTimeline(columnType: "bolus", parameters: insulinParameters, unit: .internationalUnit(), samples: samples)
            case .basal, .tempBasal:
                let samples = entries.map({ DoseSampleValue(entry: $0) })
                return encodeTimeline(columnType: "basal", parameters: insulinParameters, unit: .internationalUnit(), samples: samples)
            }
        }
        
        let carbTimelines = Dictionary(grouping: carbEntries, by: { $0.absorptionTime ?? TimeInterval(hours: 2) }).map { (absorptionTime, samples) in
            return encodeTimeline(columnType: "carb", parameters: ["delay": 5.0, "duration": absorptionTime], unit: .gram(), samples: samples)
        }
        
        let basalRateTuningSchedule = basalRateSchedule.map { (schedule) in
            return TuningSchedule(from: schedule.items)
        }
        let insulinSensitivityTuningShedule = insulinSensitivitySchedule.map { (schedule: InsulinSensitivitySchedule) -> TuningSchedule in
            let items = schedule.items.map { (item: RepeatingScheduleValue<Double>) -> RepeatingScheduleValue<Double> in
                let quantity = HKQuantity(unit: schedule.unit, doubleValue: item.value)
                let value = quantity.doubleValue(for: .milligramsPerDeciliter)
                return RepeatingScheduleValue(startTime: item.startTime, value: value)
            }
            return TuningSchedule(from: items)
        }
        let carbRatioTuningSchedule = carbRatioSchedule.map { (schedule: CarbRatioSchedule) -> TuningSchedule in
            let items = schedule.items.map { (item: RepeatingScheduleValue<Double>) -> RepeatingScheduleValue<Double> in
                let quantity = HKQuantity(unit: schedule.unit, doubleValue: item.value)
                let value = quantity.doubleValue(for: .gram())
                return RepeatingScheduleValue(startTime: item.startTime, value: value)
            }
            return TuningSchedule(from: items)
        }

        
        let payload = TuningRequest(
            version: 1,
            timezone: timeZone.identifier,
            timelines: [glucoseTimeline] + insulinTimelines + carbTimelines,
            allowedBasalRates: allowedBasalRates,
            maximumScheduleItemCount: maximumScheduleItemCount,
            minimumTimeInterval: Int(minimumTimeInterval),
            basalRateSchedule: basalRateTuningSchedule,
            insulinSensitivitySchedule: insulinSensitivityTuningShedule,
            carbRatioSchedule: carbRatioTuningSchedule,
            basalInsulinParameters: insulinParameters)
        var jsonData: Data!
        do {
            jsonData = try JSONEncoder().encode(payload)
        } catch {
            return completion(.failure(.other(error)))
        }
        
        // TODO: compression
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let task = URLSession.shared.uploadTask(with: request, from: jsonData, completionHandler: { (data, response, error) in
            if let error = error {
                return completion(.failure(.other(error)))
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return completion(.failure(.networkError))
            }
            
            if httpResponse.statusCode != 200 {
                let error = TunerError.serviceError(code: httpResponse.statusCode, body: String(data: data!, encoding: String.Encoding.utf8)!)
                return completion(.failure(error))
            }
            
            guard let data = data, !data.isEmpty else {
                let error = TunerError.serviceError(code: 200, body: "no data returned")
                return completion(.failure(error))
            }
            
            var response: TuningResponse!
            do {
                response = try JSONDecoder().decode(TuningResponse.self, from: data)
            } catch {
                return completion(.failure(.other(error)))
            }
            
            let basalItems = response.basalRateSchedule.repeatingSchedule
            let basalSchedule = BasalRateSchedule(dailyItems: basalItems, timeZone: nil)!
            let carbItems = response.carbRatioSchedule.repeatingSchedule
            let carbSchedule = CarbRatioSchedule(unit: .gram(), dailyItems: carbItems, timeZone: nil)!
            let insulinSensitivityItems = response.insulinSensitivitySchedule.repeatingSchedule
            let insulinSensitivitySchedule = InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: insulinSensitivityItems, timeZone: nil)!
            completion(.success(basalSchedule, carbSchedule, insulinSensitivitySchedule))
        })
        task.resume()
    }
    
    // MARK: - codec
    
    func encodeTimeline(columnType: String, parameters: [String: Double], unit: HKUnit, samples: [SampleValue]) -> TuningTimeline {
        let samples = samples.sorted(by: { $0.startDate < $1.startDate })
        var index: [Int] = []
        var values: [Double] = []
        var durations: [Int] = []
        for value in samples {
            index.append(Int(value.startDate.timeIntervalSince1970))
            values.append(value.quantity.doubleValue(for: unit))
            durations.append(Int(value.endDate.timeIntervalSince(value.startDate)))
        }
        deltaEncode(&index)
        deltaEncode(&values)
        deltaEncode(&durations)
        
        return TuningTimeline(columnType: columnType, parameters: parameters, index: index, values: values, durations: durations)
    }
 
    func deltaEncode<T: Numeric>(_ values: inout [T]) {
        if values.count == 0 {
            return
        }
        for index in (1..<values.count).reversed() {
            values[index] = values[index] - values[index-1]
        }
    }
}

fileprivate struct DoseSampleValue: SampleValue {
    let entry: DoseEntry
    
    var startDate: Date {
        get {
            entry.startDate
        }
    }
    
    var endDate: Date {
        get {
            entry.endDate
        }
    }
    
    var quantity: HKQuantity {
        get {
            return HKQuantity(unit: .internationalUnit(), doubleValue: entry.deliveredUnits ?? entry.programmedUnits)
        }
    }
}
