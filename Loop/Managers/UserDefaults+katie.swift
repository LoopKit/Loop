
import Foundation
import LoopKit
import MinimedKit
import RileyLinkKit
import NightscoutUploadKit


// PRIVATE MODIFICATIONS
extension UserDefaults {
    
    // Avoid polluting the original Key above.
    fileprivate enum PrivateKey: String {
        case lastUploadedNightscoutProfile = "com.loopkit.Loop.lastUploadedNightscoutProfile"
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
        
        //        var targets : [String:String] = [:]
        //        for range in
        //            loopSettings?.glucoseTargetRangeSchedule?.applyingOverride(<#T##override: TemporaryScheduleOverride##TemporaryScheduleOverride#>) ?? [:] {
        //            loopSettings?.glucoseTargetRangeScheduleApplyingOverrideIfActive?. ?? [:] {
        //            targets[range.key.rawValue] = "\(range.value.minValue) - \(range.value.maxValue)"
        //        }
        //        settings["workoutTargets"] = targets

        let profile = NightscoutProfile(
            timestamp: Date(),
            name: "Loop",
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
