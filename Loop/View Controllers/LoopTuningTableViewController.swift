//
//  LoopTuningTableViewController.swift
//  Loop
//
//  Created by marius eriksen on 12/13/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

// TODO: this should set the insulin model as well; it can be
//       retrieved from the DoseStore.
//
// TODO: total basal deliveries are emitted to health kit data;
//       so we should be able to go off of this.

import UIKit
import HealthKit
import LoopCore
import LoopKit
import LoopKitUI

public struct LoopTuningTunedParameters {
    let basalRateSchedule: BasalRateSchedule
    let carbRatioSchedule: CarbRatioSchedule
    let insulinSensitivitySchedule: InsulinSensitivitySchedule
    
    // TODO: include insulin curves, etc.
}

public protocol LoopTuningDelegate: class {
    func loopTuningCompleted(withParameters parameters: LoopTuningTunedParameters)
    func loopTuningCanceled()
}

class LoopTuningTableViewController: SetupTableViewController, IdentifiableClass {
    var doseStore: DoseStore!
    var glucoseStore: GlucoseStore!
    var carbStore: CarbStore!
    var insulinModelSettings: InsulinModelSettings?
    var timeZone: TimeZone!
    
    var basalRateSchedule: BasalRateSchedule?
    var insulinSensitivitySchedule: InsulinSensitivitySchedule?
    var carbRatioSchedule: CarbRatioSchedule?

    var allowedBasalRates: [Double]!
    var maximumScheduleItemCount: Int!
    var minimumTimeInterval: TimeInterval!
    
    var loopTuningDelegate: LoopTuningDelegate?
    
    var settings: LoopSettings!
    
//    let tuner: Tuner = RemoteTuner(smallestRequiredDataInterval: .hours(10), url: URL(string: "https://tune.basal.io/standard")!)
    let tuner: Tuner = RemoteTuner(smallestRequiredDataInterval: .hours(10), url: URL(string: "https://tune.basal.io/sydney")!)


//    let tuner: Tuner = RemoteTuner(smallestRequiredDataInterval: .hours(10), url: URL(string: "http://localhost:8080/sydney")!)

    @IBOutlet weak var statusViewCell: UITableViewCell!
    @IBOutlet weak var statusLabel: UILabel!
    
    // TODO: model selection
    
    fileprivate enum TuningError: Error {
        case dataError(error: Error)
        case testError
        case serviceError(code: Int, body: String)
        case networkError
        case noResponseError
    }

    fileprivate enum State {
        case notstarted
        case preparing
        case fetched(_ glucoseEntries: [StoredGlucoseSample], _ carbEntries: [StoredCarbEntry], _ insulinEntries: [DoseEntry])
        case done(_ basalRateSchedule: BasalRateSchedule, _ carbRatioSchedule: CarbRatioSchedule, _ sensitivitySchedule: InsulinSensitivitySchedule)
        case failure(Error)
    }
    
    private var state: State = .notstarted
    
    override func viewDidLoad() {
        super.viewDidLoad()
        footerView.primaryButton.isEnabled = true
    }
    
    override func continueButtonPressed(_ sender: Any) {
        if case .notstarted = state {
//            print(type(of: footerView.primaryButton))
//            print(type(of: footerView))
            // XXX
            
//            footerView.primaryButton.isIndicatingActivity = true
            footerView.primaryButton.isEnabled = false
            run(state: .notstarted)
        }
    }
    
    override func cancelButtonPressed(_: Any) {
        loopTuningDelegate?.loopTuningCanceled()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        guard let vc = segue.destination as? LoopTuningResultsTableViewController,
            case .done(let basalRateSchedule, let carbRatioSchedule, let sensitivitySchedule) = state else { return }
        vc.basalRateSchedule = basalRateSchedule
        vc.carbRatioSchedule = carbRatioSchedule
        vc.sensitivitySchedule = sensitivitySchedule
        vc.allowedBasalRates = allowedBasalRates
        vc.maximumScheduleItemCount = maximumScheduleItemCount
        vc.minimumTimeInterval = minimumTimeInterval
        vc.settings = settings
        vc.loopTuningDelegate = loopTuningDelegate
    }

    // MARK: - data and state management
    
    fileprivate func run(state: State) {
        print("run \(state)")
        self.state = state
        switch state {
        case .notstarted:
            run(state: .preparing)
        case .preparing:
            fetch()
        case .fetched(let glucoseEntries, let carbEntries, let insulinEntries):
            var insulinModel: TunerInsulinModel?
            // TODO: refactor InsulinModel so that we can extract these parameters directly.
            switch insulinModelSettings {
            case .exponentialPreset(.humalogNovologAdult):
                insulinModel = TunerInsulinModel(delay: .minutes(5), peak: .minutes(75), duration: .minutes(360))
            case .exponentialPreset(.humalogNovologChild):
                insulinModel = TunerInsulinModel(delay: .minutes(5), peak: .minutes(65), duration: .minutes(360))
            case .exponentialPreset(.fiasp):
                insulinModel = TunerInsulinModel(delay: .minutes(5), peak: .minutes(55), duration: .minutes(360))
            default:
                // Will use default.
                insulinModel = nil
            }
            
            tuner.estimateParameters(glucoseEntries, carbEntries, insulinEntries, insulinModel, allowedBasalRates, maximumScheduleItemCount, minimumTimeInterval, timeZone, basalRateSchedule, insulinSensitivitySchedule, carbRatioSchedule) { (result) in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let basalRateSchedule, let carbRatioSchedule, let insulinSensitivitySchedule):
                        self.run(state: .done(basalRateSchedule, carbRatioSchedule, insulinSensitivitySchedule))
                    case .failure(let error):
                        self.run(state: .failure(error))
                    }
                }
            }
        case .done(_, _, _):
            performSegue(withIdentifier: "Continue", sender: self)
            // Reset so that if we navigate back, we can do it all over again.
            // XXX
//            footerView.primaryButton.isIndicatingActivity = false
            footerView.primaryButton.isEnabled = true
            self.state = .notstarted
        case .failure(let error):
            self.present(UIAlertController(with: error), animated: true)
            // XXX
            //footerView.primaryButton.isIndicatingActivity = false
            self.state = .notstarted
        }
    }
    
    fileprivate func fetch() {
        let updateGroup = DispatchGroup()
        
        let start = Date(timeIntervalSinceNow: .hours(-24*30*3))
        
        var glucoseResult: GlucoseStoreResult<[StoredGlucoseSample]>!
        updateGroup.enter()
        glucoseStore?.getGlucoseSamples(start: start) { (result) -> Void in
            glucoseResult = result
            updateGroup.leave()
        }

        var insulinResult: DoseStoreResult<[DoseEntry]>!
        updateGroup.enter()
        doseStore?.getNormalizedDoseEntries(start: start) { (result) -> Void in
            insulinResult = result
            updateGroup.leave()
        }

        var carbResult: CarbStoreResult<[StoredCarbEntry]>!
        updateGroup.enter()
        carbStore?.getCarbEntries(start: start) { (result) -> Void in
            carbResult = result
            updateGroup.leave()
        }
        
        updateGroup.notify(qos: .utility, flags: [], queue: DispatchQueue.main) {
            var glucoseEntries: [StoredGlucoseSample] = []
            switch glucoseResult {
            case .failure(let error):
                return self.run(state: .failure(TuningError.dataError(error: error)))
            case .success(let entries):
                glucoseEntries = entries
            case .none:
                // This will always result in an error, but we'll take it through the flow.
                break
            }
            var insulinEntries: [DoseEntry] = []
            switch insulinResult {
            case .failure(let error):
                return self.run(state: .failure(TuningError.dataError(error: error)))
            case .success(let entries):
                insulinEntries = entries
            case .none:
                break
            }
            var carbEntries: [StoredCarbEntry] = []
            switch carbResult {
            case .failure(let error):
                return self.run(state: .failure(TuningError.dataError(error: error)))
            case .success(let entries):
                carbEntries = entries
            case .none:
                break
            }
            
            self.run(state: .fetched(glucoseEntries, carbEntries, insulinEntries))
        }
    }
}
