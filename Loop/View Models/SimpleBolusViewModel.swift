//
//  SimpleBolusViewModel.swift
//  Loop
//
//  Created by Pete Schwamb on 9/29/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import os.log
import SwiftUI
import LoopCore
import Intents
import LocalAuthentication

protocol SimpleBolusViewModelDelegate: class {
    
    func addGlucose(_ samples: [NewGlucoseSample], completion: @escaping (Error?) -> Void)
    
    func addCarbEntry(_ carbEntry: NewCarbEntry, replacing replacingEntry: StoredCarbEntry? ,
                      completion: @escaping (_ result: Result<StoredCarbEntry>) -> Void)

    func storeBolusDosingDecision(_ bolusDosingDecision: BolusDosingDecision, withDate date: Date)
    
    func enactBolus(units: Double, at startDate: Date)

    func insulinOnBoard(at date: Date, completion: @escaping (_ result: DoseStoreResult<InsulinValue>) -> Void)

    func computeSimpleBolusRecommendation(at date: Date, mealCarbs: HKQuantity?, manualGlucose: HKQuantity?) -> BolusDosingDecision?

    var preferredGlucoseUnit: HKUnit { get }
    
    var maximumBolus: Double { get }

    var suspendThreshold: HKQuantity { get }
}

class SimpleBolusViewModel: ObservableObject {
    
    var authenticate: AuthenticationChallenge = LocalAuthentication.deviceOwnerCheck

    enum Alert: Int {
        case maxBolusExceeded
        case carbEntryPersistenceFailure
        case carbEntrySizeTooLarge
        case manualGlucoseEntryOutOfAcceptableRange
        case manualGlucoseEntryPersistenceFailure
        case infoPopup
    }
    
    @Published var activeAlert: Alert?
    
    enum Notice: Int {
        case glucoseBelowSuspendThreshold
    }

    @Published var activeNotice: Notice?

    var isNoticeVisible: Bool { return activeNotice != nil }    

    @Published var recommendedBolus: String = "–"
    
    @Published var activeInsulin: String?

    @Published var enteredCarbAmount: String = "" {
        didSet {
            if let enteredCarbs = Self.carbAmountFormatter.number(from: enteredCarbAmount)?.doubleValue, enteredCarbs > 0 {
                carbs = HKQuantity(unit: .gram(), doubleValue: enteredCarbs)
            } else {
                carbs = nil
            }
            updateRecommendation()
        }
    }

    @Published var enteredGlucoseAmount: String = "" {
        didSet {
            if let enteredGlucose = glucoseAmountFormatter.number(from: enteredGlucoseAmount)?.doubleValue {
                glucose = HKQuantity(unit: delegate.preferredGlucoseUnit, doubleValue: enteredGlucose)
                if let glucose = glucose, glucose < suspendThreshold {
                    activeNotice = .glucoseBelowSuspendThreshold
                } else {
                    activeNotice = nil
                }
            } else {
                glucose = nil
            }
            updateRecommendation()
        }
    }

    @Published var enteredBolusAmount: String {
        didSet {
            if let enteredBolusAmount = Self.doseAmountFormatter.number(from: enteredBolusAmount)?.doubleValue, enteredBolusAmount > 0 {
                bolus = HKQuantity(unit: .internationalUnit(), doubleValue: enteredBolusAmount)
            } else {
                bolus = nil
            }
        }
    }
    
    private var carbs: HKQuantity? = nil
    private var glucose: HKQuantity? = nil
    private var bolus: HKQuantity? = nil
    
    var glucoseUnit: HKUnit { return delegate.preferredGlucoseUnit }
    
    var suspendThreshold: HKQuantity { return delegate.suspendThreshold }

    private var recommendation: Double? = nil {
        didSet {
            if let recommendation = recommendation, let recommendationString = Self.doseAmountFormatter.string(from: recommendation) {
                recommendedBolus = recommendationString
                enteredBolusAmount = recommendationString
            } else {
                recommendedBolus = NSLocalizedString("–", comment: "String denoting lack of a recommended bolus amount in the simple bolus calculator")
                enteredBolusAmount = Self.doseAmountFormatter.string(from: 0.0)!
            }
        }
    }
    
    private var dosingDecision: BolusDosingDecision?
    
    private var recommendationDate: Date?

    private static let doseAmountFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()
    
    private static let carbAmountFormatter: NumberFormatter = {
        let quantityFormatter = QuantityFormatter()
        quantityFormatter.setPreferredNumberFormatter(for: .gram())
        return quantityFormatter.numberFormatter
    }()

    enum ActionButtonAction {
        case saveWithoutBolusing
        case saveAndDeliver
        case enterBolus
        case deliver
    }
    
    var hasDataToSave: Bool {
        return glucose != nil || carbs != nil
    }
    
    var hasBolusEntryReadyToDeliver: Bool {
        return bolus != nil
    }
    
    var actionButtonAction: ActionButtonAction {
        switch (hasDataToSave, hasBolusEntryReadyToDeliver) {
        case (true, true): return .saveAndDeliver
        case (true, false): return .saveWithoutBolusing
        case (false, true): return .deliver
        case (false, false): return .enterBolus
        }
    }
    
    var carbPlaceholder: String {
        Self.carbAmountFormatter.string(from: 0.0)!
    }

    private let glucoseAmountFormatter: NumberFormatter
    private let delegate: SimpleBolusViewModelDelegate
    private let log = OSLog(category: "SimpleBolusViewModel")
    
    private lazy var bolusVolumeFormatter = QuantityFormatter(for: .internationalUnit())

    var maximumBolusAmountString: String? {
        return bolusVolumeFormatter.numberFormatter.string(from: delegate.maximumBolus) ?? String(delegate.maximumBolus)
    }

    init(delegate: SimpleBolusViewModelDelegate) {
        self.delegate = delegate
        let glucoseQuantityFormatter = QuantityFormatter()
        glucoseQuantityFormatter.setPreferredNumberFormatter(for: delegate.preferredGlucoseUnit)
        glucoseAmountFormatter = glucoseQuantityFormatter.numberFormatter
        enteredBolusAmount = Self.doseAmountFormatter.string(from: 0.0)!
        updateRecommendation()
        dosingDecision = BolusDosingDecision()
    }
    
    func updateRecommendation() {
        let recommendationDate = Date()
        if carbs != nil || glucose != nil {
            dosingDecision = delegate.computeSimpleBolusRecommendation(at: recommendationDate, mealCarbs: carbs, manualGlucose: glucose)
            if let decision = dosingDecision, let bolusRecommendation = decision.recommendedBolus {
                recommendation = bolusRecommendation.amount
            } else {
                recommendation = nil
            }
            
            if let decision = dosingDecision, let insulinOnBoard = decision.insulinOnBoard, insulinOnBoard.value > 0, glucose != nil {
                activeInsulin = Self.doseAmountFormatter.string(from: insulinOnBoard.value)
            } else {
                activeInsulin = nil
            }
            self.recommendationDate = recommendationDate
        } else {
            dosingDecision = nil
            recommendation = nil
            activeInsulin = nil
            self.recommendationDate = nil
        }
    }
    
    func saveAndDeliver(completion: @escaping (Bool) -> Void) {
        if let bolus = bolus {
            guard bolus.doubleValue(for: .internationalUnit()) <= delegate.maximumBolus else {
                presentAlert(.maxBolusExceeded)
                completion(false)
                return
            }
        }

        if let glucose = glucose {
            guard LoopConstants.validManualGlucoseEntryRange.contains(glucose) else {
                presentAlert(.manualGlucoseEntryOutOfAcceptableRange)
                completion(false)
                return
            }
        }
        
        if let carbs = carbs {
            guard carbs <= LoopConstants.maxCarbEntryQuantity else {
                presentAlert(.carbEntrySizeTooLarge)
                completion(false)
                return
            }
        }
        
        let saveDate = Date()

        // Authenticate the bolus before saving anything
        func authenticateIfNeeded(_ completion: @escaping (Bool) -> Void) {
            if let bolus = bolus, bolus.doubleValue(for: .internationalUnit()) > 0 {
                let message = String(format: NSLocalizedString("Authenticate to Bolus %@ Units", comment: "The message displayed during a device authentication prompt for bolus specification"), enteredBolusAmount)
                authenticate(message) {
                    switch $0 {
                    case .success:
                        completion(true)
                    case .failure:
                        completion(false)
                    }
                }
            } else {
                completion(true)
            }
        }
        
        func saveManualGlucose(_ completion: @escaping (Bool) -> Void) {
            if let glucose = glucose {
                let manualGlucoseSample = NewGlucoseSample(date: saveDate, quantity: glucose, isDisplayOnly: false, wasUserEntered: true, syncIdentifier: UUID().uuidString)
                delegate.addGlucose([manualGlucoseSample]) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.presentAlert(.manualGlucoseEntryPersistenceFailure)
                            self.log.error("Failed to add manual glucose entry: %{public}@", String(describing: error))
                            completion(false)
                        } else {
                            completion(true)
                        }
                    }
                }
            } else {
                completion(true)
            }
        }
        
        func saveCarbs(_ completion: @escaping (Bool) -> Void) {
            if let carbs = carbs {
                
                let interaction = INInteraction(intent: NewCarbEntryIntent(), response: nil)
                interaction.donate { [weak self] (error) in
                    if let error = error {
                        self?.log.error("Failed to donate intent: %{public}@", String(describing: error))
                    }
                }
                
                let carbEntry = NewCarbEntry(date: saveDate, quantity: carbs, startDate: saveDate, foodType: nil, absorptionTime: nil)
                
                delegate.addCarbEntry(carbEntry, replacing: nil) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .failure(let error):
                            self.presentAlert(.carbEntryPersistenceFailure)
                            self.log.error("Failed to add carb entry: %{public}@", String(describing: error))
                            completion(false)
                        case .success(let storedEntry):
                            self.dosingDecision?.carbEntry = storedEntry
                            completion(true)
                        }
                    }
                }
            } else {
                completion(true)
            }
        }
        
        func enactBolus() {
            if let bolusVolume = bolus?.doubleValue(for: .internationalUnit()), bolusVolume > 0 {
                delegate.enactBolus(units: bolusVolume, at: saveDate)
                dosingDecision?.requestedBolus = bolusVolume
            }
        }
        
        func saveBolusDecision() {
            if let decision = dosingDecision, let recommendationDate = recommendationDate {
                delegate.storeBolusDosingDecision(decision, withDate: recommendationDate)
            }
        }
        
        func finishWithResult(_ success: Bool) {
            saveBolusDecision()
            completion(success)
        }
        
        authenticateIfNeeded { (success) in
            if success {
                saveManualGlucose { (success) in
                    if success {
                        saveCarbs { (success) in
                            if success {
                                enactBolus()
                            }
                            finishWithResult(success)
                        }
                    } else {
                        finishWithResult(false)
                    }
                }
            } else {
                finishWithResult(false)
            }
        }
    }
    
    private func presentAlert(_ alert: Alert) {
        dispatchPrecondition(condition: .onQueue(.main))

        // As of iOS 13.6 / Xcode 11.6, swapping out an alert while one is active crashes SwiftUI.
        guard activeAlert == nil else {
            return
        }

        activeAlert = alert
    }
    
    func restoreUserActivityState(_ activity: NSUserActivity) {
        if let entry = activity.newCarbEntry {
            carbs = entry.quantity
        }
    }
}

extension SimpleBolusViewModel.Alert: Identifiable {
    var id: Self { self }
}
