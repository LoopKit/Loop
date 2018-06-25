//
//  NightscoutUploader+Profile.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import NightscoutUploadKit

private let defaultNightscoutProfilePath = "/api/v1/profile"

class NightscoutTimeFormat: NSObject {
    private static var formatterISO8601 : DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: Calendar.Identifier.iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssX"
        
        return formatter
    }
    
    static func timestampStrFromDate(_ date: Date) -> String {
        return formatterISO8601.string(from: date)
    }
}

public class NightscoutProfile {
    
    let timestamp : Date
    let name : String
    let rangeSchedule : GlucoseRangeSchedule
    let sensitivity : InsulinSensitivitySchedule
    let carbs : CarbRatioSchedule
    let basal : BasalRateSchedule
    let timezone : String
    let dia : Double
    let settings : [String:Any]
    
    public init(timestamp: Date, name: String, rangeSchedule: GlucoseRangeSchedule,
                sensitivity: InsulinSensitivitySchedule,
                carbs: CarbRatioSchedule,
                basal : BasalRateSchedule,
                timezone : TimeZone,
                dia : Double,
                settings : [String:Any] = [:]
                ) {
        self.timestamp = timestamp
        self.name = name
        self.rangeSchedule = rangeSchedule
        self.sensitivity = sensitivity
        self.carbs = carbs
        self.basal = basal
        self.timezone = timezone.identifier
        self.dia = dia
        self.settings = settings
    }
    
    private func formatItem(_ time: TimeInterval, _ value: Any) -> [String:Any] {
        let hours = Int(time / 3600)
        let minutes = (time / 60).truncatingRemainder(dividingBy: 60)
        var rep : [String: Any] = [:]
        rep["time"] = String(format:"%02i:%02i", hours, minutes)
        rep["value"] = value
        rep["timeAsSeconds"] = Int(time)
        return rep
    }
    
    public var json : String? {
        do {
            var dict = dictionaryRepresentation
            dict["created_at"] = "<blanked>"
            dict["startDate"] = "<blanked>"
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            if let encodedData = String(data: data, encoding: .utf8) {
                return encodedData
            }
        } catch (let error) {
            NSLog("NightscoutProfile encoding to json error: \(error)")
        }
        return nil
    }
    
    public var dictionaryRepresentation: [String: Any] {
        var profile : [String: Any] = [:]
        profile["dia"] = self.dia
        profile["carbs_hr"] = "0"
        profile["delay"] = "0"
        
        profile["timezone"] = timezone
        
        var target_low = [[String:Any]]()
        var target_high = [[String:Any]]()
        for item in self.rangeSchedule.items {
            target_low.append(formatItem(item.startTime, item.value.minValue))
            target_high.append(formatItem(item.startTime, item.value.maxValue))
        }
        profile["target_low"] = target_low
        profile["target_high"] = target_high

        var sens = [[String:Any]]()
        for item in self.sensitivity.items {
            sens.append(formatItem(item.startTime, item.value))
        }
        profile["sens"] = sens
      
        var basal = [[String:Any]]()
        for item in self.basal.items {
            basal.append(formatItem(item.startTime, item.value))
        }
        profile["basal"] = basal

        var carbratio = [[String:Any]]()
        for item in self.carbs.items {
            carbratio.append(formatItem(item.startTime, item.value))
        }
        profile["carbratio"] = carbratio

        var store : [String: Any] = [:]
        let profileName = "Default"
        store[profileName] = profile
        
        var rval : [String: Any] = [:]
        
        rval["defaultProfile"] = profileName
        rval["mills"] = "0" // ?
        rval["units"] = self.rangeSchedule.unit.localizedShortUnitString
        rval["startDate"] = NightscoutTimeFormat.timestampStrFromDate(timestamp)
        rval["created_at"] = NightscoutTimeFormat.timestampStrFromDate(timestamp)
        rval["enteredBy"] = "loop"
        rval["store"] = store
        var settings = self.settings
        settings.removeValue(forKey: "glucoseTargetRangeSchedule")
        rval["loopSettings"] = settings
        return rval
    }
}

extension NightscoutUploader {
    
    public func uploadProfile(_ profile: NightscoutProfile, completion: @escaping (Either<[String],Error>) -> Void) {
        let inFlight = [profile]
        
        profilePostToNS(inFlight.map({$0.dictionaryRepresentation}), endpoint: defaultNightscoutProfilePath) { (result) in
            switch result {
            case .failure(let error):
                self.errorHandler?(error, "Uploading nightscout profile records")
                // Requeue
                //self.treatmentsQueue.append(contentsOf: inFlight)
            case .success(_):
                //if let last = inFlight.last {
                  //  self.lastStoredTreatmentTimestamp = last.timestamp
                //}
                break
            }
            completion(result)
        }
    }
    
    // Blunt copies but internal protection level makes them inaccessible
    func profilePostToNS(_ json: [Any], endpoint:String, completion: @escaping (Either<[String],Error>) -> Void) {
        if json.count == 0 {
            completion(.success([]))
            return
        }
        
        profileCallNS(json, endpoint: endpoint, method: "POST") { (result) in
            switch result {
            case .success(let json):
                guard let insertedEntries = json as? [[String: Any]] else {
                    completion(.failure(UploadError.invalidResponse(reason: "Expected array of objects in JSON response")))
                    return
                }
                
                let ids = insertedEntries.map({ (entry: [String: Any]) -> String in
                    if let id = entry["_id"] as? String {
                        return id
                    } else {
                        // Upload still succeeded; likely that this is an old version of NS
                        // Instead of failing (which would cause retries later, we just mark
                        // This entry has having an id of 'NA', which will let us consider it
                        // uploaded.
                        //throw UploadError.invalidResponse(reason: "Invalid/missing id in response.")
                        return "NA"
                    }
                })
                completion(.success(ids))
            case .failure(let error):
                completion(.failure(error))
            }
            
        }
    }
    
    func profileCallNS(_ json: Any?, endpoint:String, method:String, completion: @escaping (Either<Any,Error>) -> Void) {
        let uploadURL = siteURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: uploadURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiSecret.sha1, forHTTPHeaderField: "api-secret")
        
        do {
            
            if let json = json {
                let sendData = try JSONSerialization.data(withJSONObject: json, options: [])
                let task = URLSession.shared.uploadTask(with: request, from: sendData, completionHandler: { (data, response, error) in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(UploadError.invalidResponse(reason: "Response is not HTTPURLResponse")))
                        return
                    }
                    
                    if httpResponse.statusCode != 200 {
                        let error = UploadError.httpError(status: httpResponse.statusCode, body:String(data: data!, encoding: String.Encoding.utf8)!)
                        completion(.failure(error))
                        return
                    }
                    
                    guard let data = data else {
                        completion(.failure(UploadError.invalidResponse(reason: "No data in response")))
                        return
                    }
                    
                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
                        completion(.success(json))
                    } catch {
                        completion(.failure(error))
                        return
                    }
                })
                task.resume()
            } else {
                let task = URLSession.shared.dataTask(with: request, completionHandler: { (data, response, error) in
                    if let error = error {
                        completion(.failure(error))
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(.failure(UploadError.invalidResponse(reason: "Response is not HTTPURLResponse")))
                        return
                    }
                    
                    if httpResponse.statusCode != 200 {
                        let error = UploadError.httpError(status: httpResponse.statusCode, body:String(data: data!, encoding: String.Encoding.utf8)!)
                        completion(.failure(error))
                        return
                    }
                    
                    guard let data = data else {
                        completion(.failure(UploadError.invalidResponse(reason: "No data in response")))
                        return
                    }
                    
                    do {
                        let json = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions())
                        completion(.success(json))
                    } catch {
                        completion(.failure(error))
                        return
                    }
                })
                task.resume()
            }
            
        } catch let error {
            completion(.failure(error))
        }
    }
    
}
