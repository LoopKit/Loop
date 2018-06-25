
import Foundation
import LoopKit
import MinimedKit
import RileyLinkKit
import NightscoutUploadKit


// PRIVATE MODIFICATIONS
extension UserDefaults {

    // Avoid polluting the original Key above.
    fileprivate enum PrivateKey: String {
        case minimumBasalRateSchedule = "com.loudnate.Loop.MinBasalRateSchedule"
        case foodStats = "com.loopkit.Loop.foodStats"
        case foodManagerNeedUpload = "com.loopkit.Loop.foodNeedUpload"
        case pumpDetachedMode = "com.loopkit.Loop.pumpDetachedMode"
        case lastUploadedNightscoutProfile = "com.loopkit.Loop.lastUploadedNightscoutProfile"
        case pendingTreatments = "com.loopkit.Loop.pendingTreatments"
        case absorptionTimeMultiplier = "com.loopkit.Loop.absorptionTimeMultiplier"
    }

    var minimumBasalRateSchedule: BasalRateSchedule? {
        get {
            if let rawValue = dictionary(forKey: PrivateKey.minimumBasalRateSchedule.rawValue) {
                return BasalRateSchedule(rawValue: rawValue)
            } else {
                return nil
            }
        }
        set {
            set(newValue?.rawValue, forKey: PrivateKey.minimumBasalRateSchedule.rawValue)
        }
    }


    var textDump : String {
        return self.dictionaryRepresentation().debugDescription
    }

    var foodStats : [String: [String: Int]] {
        get {
            if let rawValue = dictionary(forKey: PrivateKey.foodStats.rawValue) {
                var ret : [String: [String: Int]] = [:]
                for raw in rawValue {
                    if let val = raw.value as? [String: Int] {
                        let key = raw.key
                        ret[key] = val
                    }
                }
                return ret
            } else {
                return [:]
            }
        }
        set {
            set(newValue, forKey: PrivateKey.foodStats.rawValue)
        }
    }

    var foodManagerNeedUpload : [String] {
        get {
            return array(forKey: PrivateKey.foodManagerNeedUpload.rawValue) as? [String] ?? []
        }
        set {
            set(newValue, forKey: PrivateKey.foodManagerNeedUpload.rawValue)
        }
    }

    var pendingTreatments: [(type: Int, date: Date, note: String)] {
        get {
            var ret : [(type: Int, date: Date, note: String)] = []
            for element in array(forKey: PrivateKey.pendingTreatments.rawValue) as? [[String:Any]] ?? [] {
                guard let type = element["type"] as? Int, let date = element["date"] as? Date, let note = element["note"] as? String else {
                    NSLog("Cannot parse stored pendingTreatment \(element)")
                    continue
                }
                ret.append((type: type, date: date, note: note))
            }
            return ret
        }
        set {
            var raw : [[String:Any]] = []
            for value in newValue {
                raw.append([
                    "type": value.type,
                    "date": value.date,
                    "note": value.note
                    ])
            }
            set(raw, forKey: PrivateKey.pendingTreatments.rawValue)
        }
    }

    var pumpDetachedMode: Date? {
        get {
            let value = double(forKey: PrivateKey.pumpDetachedMode.rawValue)
            if value > 0 {
                return Date(timeIntervalSinceReferenceDate: value)
            } else {
                return nil
            }
        }
        set {
            if newValue == nil {
                removeObject(forKey: PrivateKey.pumpDetachedMode.rawValue)
            } else {
                set(newValue?.timeIntervalSinceReferenceDate, forKey: PrivateKey.pumpDetachedMode.rawValue)
            }
        }
    }

    var absorptionTimeMultiplier : Double {
        get {
            let value = double(forKey: PrivateKey.absorptionTimeMultiplier.rawValue)
            // default
            if value <= 0.0 {
                return 0.9
            }
            return value
        }
        set {
            set(newValue, forKey: PrivateKey.absorptionTimeMultiplier.rawValue)
        }
    }

    var lastUploadedNightscoutProfile: String {
        get {
            return string(forKey: PrivateKey.lastUploadedNightscoutProfile.rawValue) ?? "{}"
        }
        set {
            set(newValue, forKey: PrivateKey.lastUploadedNightscoutProfile.rawValue)
        }
    }

    func uploadProfile(uploader: NightscoutUploader, retry: Int = 0) {
        NSLog("uploadProfile")
        guard let glucoseTargetRangeSchedule = loopSettings?.glucoseTargetRangeSchedule,
            let insulinSensitivitySchedule = insulinSensitivitySchedule,
            let carbRatioSchedule = carbRatioSchedule,
            let basalRateSchedule = basalRateSchedule

            else {
                NSLog("uploadProfile - missing data")

                return
        }
        if retry > 5 {
            NSLog("uploadProfile - too many retries")
            return
        }
        var settings = loopSettings?.rawValue ?? [:]
        settings["minBasal"] = minimumBasalRateSchedule?.rawValue
        settings["pumpId"] = pumpSettings?.pumpID
        settings["pumpRegion"] = pumpSettings?.pumpRegion.description
        settings["cgmSource"] = cgm?.rawValue
        var targets : [String:String] = [:]
        for range in loopSettings?.glucoseTargetRangeSchedule?.overrideRanges ?? [:] {
            targets[range.key.rawValue] = "\(range.value.minValue) - \(range.value.maxValue)"
        }
        settings["workoutTargets"] = targets
        let profile = NightscoutProfile(
            timestamp: Date(),
            name: "Loop2",
            rangeSchedule: glucoseTargetRangeSchedule,
            sensitivity: insulinSensitivitySchedule,
            carbs: carbRatioSchedule,
            basal : basalRateSchedule,
            timezone : TimeZone.current,
            dia : (insulinModelSettings?.model.effectDuration ?? 0) / 3600,
            settings : settings
        )
        guard let json = profile.json else {
            NSLog("uploadProfile - could not generate json!")
            return
        }
        print("+++++++++")
        print(json)
        print("+++++++++")
        if json != lastUploadedNightscoutProfile {
            uploader.uploadProfile(profile) { (result) in
                switch result {
                case .failure(let error):
                    NSLog("uploadProfile failed, try \(retry): \(error)")
                    // Try again with linear backoff, this is not great as updates afterwards
                    // can potentially be overwritten.
                    let retries = retry + 1
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(300 * retries) ) {
                        self.uploadProfile(uploader: uploader, retry: retries)
                    }
                case .success(_):
                    NSLog("uploadProfile - success")
                    self.lastUploadedNightscoutProfile = json
                }
            }
        } else {
            NSLog("uploadProfile - no change!")
        }
    }

}

