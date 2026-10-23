//
//  InsulinDeliveryLogViewModel.swift
//  Loop
//
//  Created by Cameron Ingham on 7/16/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopAlgorithm
import LoopKit
import os.log

@MainActor
@Observable
class InsulinDeliveryLogViewModel {
    
    enum FilterOptions: Hashable, CaseIterable {
        case userInitiated
        case all
        
        var localizedMenuTitle: String {
            switch self {
            case .userInitiated:
                NSLocalizedString("Self-Initiated Events", comment: "")
            case .all:
                NSLocalizedString("All Events", comment: "")
            }
        }
    }
    
    enum LogEventDisplay: Hashable, Identifiable {
        case title(id: UUID, String)
        case event(InsulinDeliveryLogEvent)
        
        var id: Int {
            hashValue
        }
    }
    
    struct DisplayData: Hashable {
        let insulinDeliveryState: InsulinDeliveryOverview.State, insulinDeliveryStateUpdatedDate: Date, currentBasalRate: DatedQuantity, lastAutoBolus: DatedQuantity?, totalInsulinDelivered: LoopQuantity, typicalInsulinDelivered: DatedQuantity?, events: [InsulinDeliveryLogEvent]
    }
    
    enum State: Hashable {
        case loading
        case fetched(DisplayData)
        case refreshing(DisplayData)
    }
    
    let totalDeliveredFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter(for: .internationalUnit)
        
        formatter.numberFormatter.maximumFractionDigits = 1
        
        return formatter
    }()
    
    private let loopDataManager: LoopDataManager
    private let pumpManager: PumpManager
    
    private let log = OSLog(category: "InsulinDeliveryLogViewModel")
    
    private(set) var state: State
    
    var selectedFilterOption: FilterOptions = .all
    
    var logEventDisplays: [LogEventDisplay] {
        var displayEvents: [LogEventDisplay] = []
        
        switch state {
        case .fetched(let data), .refreshing(let data):
            data.events.filter {
                switch selectedFilterOption {
                case .userInitiated:
                    switch $0.type {
                    case .automation,
                            .preset,
                            .pumpEvent(.basal(.manualTempBasal, rate: _), _),
                            .pumpEvent(.insulin, _),
                            .pumpEvent(.bolus(.correction, _, _), _),
                            .pumpEvent(.bolus(.meal, _, _), _),
                            .pumpEvent(.bolus(.external, _, _), _):
                        return true
                    default:
                        return false
                    }
                case .all:
                    return true
                }
            }.segmentItemsByHour().forEach { events in
                displayEvents.append(.title(id: UUID(), "\(events.start.formatted(date: .omitted, time: .shortened)) - \(events.end.formatted(date: .omitted, time: .shortened))"))
                events.events.forEach { event in
                    displayEvents.append(.event(event))
                }
            }
        case .loading:
            break
        }
        
        return displayEvents
    }
    
    var eventCount: Int {
        logEventDisplays.filter { display in
            switch display {
            case .event:
                return true
            case .title:
                return false
            }
        }.count
    }
    
    private var doseStoreObserver: Any? {
        willSet {
            if let observer = doseStoreObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
    
    private var doseStore: DoseStore! {
        didSet {
            if let doseStore = doseStore {
                doseStoreObserver = NotificationCenter.default.addObserver(forName: nil, object: doseStore, queue: OperationQueue.main, using: { [weak self] note in

                    switch note.name {
                    case DoseStore.valuesDidChange:
                        Task { @MainActor in
                            await self?.fetchData()
                        }
                    default:
                        break
                    }
                })
            } else {
                doseStoreObserver = nil
            }
        }
    }
    
    init(
        loopDataManager: LoopDataManager,
        pumpManager: PumpManager,
        initialState: State = .loading
    ) {
        self.loopDataManager = loopDataManager
        self.pumpManager = pumpManager
        self.state = initialState
        
        self.doseStore = (loopDataManager.doseStore as? DoseStore)
        
        Task {
            await fetchData()
        }
    }

    func deleteDose(_ doseEntry: DoseEntry) async {
        await withCheckedContinuation { continuation in
            doseStore.deleteDose(doseEntry) { error in
                if let error {
                    self.log.error("Error deleting dose: %{public}@", String(describing: error))
                }
                continuation.resume()
            }
        }
    }

    func fetchData() async {
        if case let .fetched(data) = state {
            state = .refreshing(data)
        }
                
        // fetch all events within the last 24hrs
        let fetchedDate = Date()
        let startDate = fetchedDate.addingTimeInterval(.days(-1))
        
        let statusState = fetchStatusState()
        let (totalInsulinDelivered, typicalInsulinDelivered) = await fetchInsulinDeliveredToday()
        let doses = await fetchDoses(since: startDate)
        let lastAutoBolus = fetchLastAutoBolus(doses: doses)
        let decisions = await fetchDosingDecisions(doses.compactMap(\.decisionId))
        
        // map raw event data into delivery log events for display
        var events = [InsulinDeliveryLogEvent]()
        handleDoseEvents(doses: doses, decisions: decisions, fetchedDate: fetchedDate, events: &events)
        handleAutomationEvents(&events)
        handlePresetEvents(startDate: startDate, &events)
        
        // update the state of delivery log with the fetched & mapped data
        state = .fetched(
            .init(
                insulinDeliveryState: statusState,
                insulinDeliveryStateUpdatedDate: fetchedDate,
                currentBasalRate: fetchCurrentBasal() ?? DatedQuantity(date: TestingDate.currentTestingDate(), quantity: LoopQuantity(unit: .internationalUnitsPerHour, doubleValue: 0)),
                lastAutoBolus: lastAutoBolus,
                totalInsulinDelivered: totalInsulinDelivered,
                typicalInsulinDelivered: typicalInsulinDelivered,
                events: events
            )
        )
    }
    
    private func fetchStatusState() -> InsulinDeliveryOverview.State {
        var insulinSuspended = false
        if case .suspended = pumpManager.status.basalDeliveryState {
            insulinSuspended = true
        }
        
        let automationEnabled = loopDataManager.settingsProvider.dosingEnabled
        let automatedTreatmentState = pumpManager.pumpManagerDelegate?.automatedTreatmentState ?? .neutralNoOverride

        if insulinSuspended {
            return .error(status: .suspended)
        } else if fetchCurrentBasal() == nil {
            return .error(status: .noDelivery)
        } else if automationEnabled {
            let basalStatus: InsulinDeliveryOverview.State.AutomatedBasalStatus
            switch automatedTreatmentState {
            case .neutralNoOverride, .neutralOverride:
                basalStatus = .scheduled
            case .increasedInsulin:
                basalStatus = .increased
            case .decreasedInsulin, .minimumDelivery:
                basalStatus = .decreased
            }
            
            return .automationOn(basalStatus: basalStatus, preset: loopDataManager.temporaryPresetsManager.activePreset)
        } else {
            return .automationOff
        }
    }
    
    private func fetchCurrentBasal() -> DatedQuantity? {
        let date = loopDataManager.lastLoopCompleted ?? Date()
        
        guard let scheduledBasalRate = loopDataManager.settings.basalRateSchedule?.value(at: date) else {
            return nil
        }
        
        guard let currentBasalRate = pumpManager.status.basalDeliveryState?.currentBasalRate(currentScheduledBasalRate: scheduledBasalRate) else {
            return nil
        }

        return DatedQuantity(
            date: date,
            quantity: LoopQuantity(
                unit: .internationalUnitsPerHour,
                doubleValue: currentBasalRate
            )
        )
    }
    
    private func fetchLastAutoBolus(doses: [DoseEntry]) -> DatedQuantity? {
        guard let lastAutoBolusDose = doses.last(where: { $0.type == .bolus && $0.automatic == true }) else {
            return nil
        }
        
        return DatedQuantity(date: lastAutoBolusDose.startDate, quantity: LoopQuantity(unit: .internationalUnit, doubleValue: lastAutoBolusDose.deliveredUnits ?? lastAutoBolusDose.value))
    }
    
    private func fetchDoses(since startDate: Date) async -> [DoseEntry] {
        (try? await loopDataManager.doseStore.getNormalizedDoseEntries(start: startDate, end: nil)) ?? []
    }
    
    private func fetchDosingDecisions(_ ids: [UUID]) async -> [LightDosingDecision] {
        (try? await loopDataManager.dosingDecisionStore.findDosingDecisionsByIds(ids)) ?? []
    }
    
    /// Today's total, and the usual amount by this time of day when there's enough history.
    private func fetchInsulinDeliveredToday() async -> (LoopQuantity, DatedQuantity?) {
        guard let history = try? await loopDataManager.insulinDeliveryHistory(days: 14) else {
            return (await LoopQuantity(unit: .internationalUnit, doubleValue: loopDataManager.totalDeliveredToday()?.value ?? 0), nil)
        }
        let today = history.totals(from: Calendar.current.startOfDay(for: history.end), to: history.end).total
        let typical = history.typicalDelivery(by: history.end).map {
            DatedQuantity(date: history.end, quantity: LoopQuantity(unit: .internationalUnit, doubleValue: $0.median))
        }
        return (LoopQuantity(unit: .internationalUnit, doubleValue: today), typical)
    }
    
    private func handleBasalEvent(dose: DoseEntry, decision: LightDosingDecision?, events: inout [InsulinDeliveryLogEvent]) {
        let automationEnabledDuringDose = loopDataManager.automationHistory.automationEnabled(at: dose.startDate) ?? loopDataManager.settingsProvider.dosingEnabled
        
        if dose.type == .tempBasal && dose.automatic == false {
            events.append(
                InsulinDeliveryLogEvent(
                    id: dose.syncIdentifier ?? UUID().uuidString,
                    type: .pumpEvent(
                        .basal(
                            .manualTempBasal(endDate: dose.endDate),
                            rate: LoopQuantity(
                                unit: .internationalUnitsPerHour,
                                doubleValue: dose.unitsPerHour
                            )
                        ),
                        dose
                    ),
                    date: dose.startDate
                )
            )
        } else if automationEnabledDuringDose {
            if let decision {
                if decision.scheduleOverride != nil {
                    events.append(
                        InsulinDeliveryLogEvent(
                            id: dose.syncIdentifier ?? UUID().uuidString,
                            type: .pumpEvent(
                                .basal(
                                    .automatedPresetBasal,
                                    rate: LoopQuantity(
                                        unit: .internationalUnitsPerHour,
                                        doubleValue: dose.unitsPerHour
                                    )
                                ),
                                dose
                            ),
                            date: dose.startDate
                        )
                    )
                } else {
                    if let direction = decision.automaticDoseRecommendation?.direction {
                        switch direction {
                        case .decrease:
                            events.append(
                                InsulinDeliveryLogEvent(
                                    id: dose.syncIdentifier ?? UUID().uuidString,
                                    type: .pumpEvent(
                                        .basal(
                                            .automationOn(basalStatus: .lessThanScheduled),
                                            rate: LoopQuantity(
                                                unit: .internationalUnitsPerHour,
                                                doubleValue: dose.unitsPerHour
                                            )
                                        ),
                                        dose
                                    ),
                                    date: dose.startDate
                                )
                            )
                        case .neutral:
                            events.append(
                                InsulinDeliveryLogEvent(
                                    id: dose.syncIdentifier ?? UUID().uuidString,
                                    type: .pumpEvent(
                                        .basal(
                                            .automationOn(basalStatus: .scheduled),
                                            rate: LoopQuantity(
                                                unit: .internationalUnitsPerHour,
                                                doubleValue: dose.unitsPerHour
                                            )
                                        ),
                                        dose
                                    ),
                                    date: dose.startDate
                                )
                            )
                        case .increase:
                            events.append(
                                InsulinDeliveryLogEvent(
                                    id: dose.syncIdentifier ?? UUID().uuidString,
                                    type: .pumpEvent(
                                        .basal(
                                            .automationOn(basalStatus: .moreThanScheduled),
                                            rate: LoopQuantity(
                                                unit: .internationalUnitsPerHour,
                                                doubleValue: dose.unitsPerHour
                                            )
                                        ),
                                        dose
                                    ),
                                    date: dose.startDate
                                )
                            )
                        }
                    } else {
                        log.error("No `decision.automaticDoseRecommendation`")
                    }
                }
            } else if let scheduledBasalRate = dose.scheduledBasalRate, scheduledBasalRate.doubleValue(for: .internationalUnitsPerHour) == dose.value {
                events.append(
                    InsulinDeliveryLogEvent(
                        id: dose.syncIdentifier ?? UUID().uuidString,
                        type: .pumpEvent(
                            .basal(
                                .automationOn(basalStatus: .scheduled),
                                rate: LoopQuantity(
                                    unit: .internationalUnitsPerHour,
                                    doubleValue: dose.unitsPerHour
                                )
                            ),
                            dose
                        ),
                        date: dose.startDate
                    )
                )
            } else {
                log.error("No `decision` or `scheduledBasalRate`")
            }
        } else {
            events.append(
                InsulinDeliveryLogEvent(
                    id: dose.syncIdentifier ?? UUID().uuidString,
                    type: .pumpEvent(
                        .basal(
                            .automationOff,
                            rate: LoopQuantity(
                                unit: .internationalUnitsPerHour,
                                doubleValue: dose.unitsPerHour
                            )
                        ),
                        dose
                    ),
                    date: dose.startDate
                )
            )
        }
    }
    
    private func handleBolusEvents(dose: DoseEntry, decision: LightDosingDecision?, events: inout [InsulinDeliveryLogEvent]) {
        if dose.manuallyEntered {
            events.append(
                InsulinDeliveryLogEvent(
                    id: dose.syncIdentifier ?? UUID().uuidString,
                    type: .pumpEvent(
                        .bolus(
                            .external,
                            programmedAmount: LoopQuantity(
                                unit: .internationalUnit,
                                doubleValue: dose.programmedUnits
                            ),
                            deliveryAmount: LoopQuantity(
                                unit: .internationalUnit,
                                doubleValue: dose.deliveredUnits ?? dose.programmedUnits
                            )
                        ),
                        dose
                    ),
                    date: dose.startDate
                )
            )
        } else if dose.automatic == true {
            events.append(
                InsulinDeliveryLogEvent(
                    id: dose.syncIdentifier ?? UUID().uuidString,
                    type: .pumpEvent(
                        .bolus(
                            .automated,
                            programmedAmount: LoopQuantity(
                                unit: .internationalUnit,
                                doubleValue: dose.programmedUnits
                            ),
                            deliveryAmount: LoopQuantity(
                                unit: .internationalUnit,
                                doubleValue: dose.deliveredUnits ?? dose.programmedUnits
                            )
                        ),
                        dose
                    ),
                    date: dose.startDate
                )
            )
        } else {
            if let recommendedUnits = decision?.manualBolusRecommendation?.recommendation.amount {
                if let carbEntry = decision?.carbEntry {
                    events.append(
                        InsulinDeliveryLogEvent(
                            id: decision?.syncIdentifier.uuidString ?? UUID().uuidString,
                            type: .pumpEvent(
                                .bolus(
                                    .meal(
                                        recommendedAmount: LoopQuantity(
                                            unit: .internationalUnit,
                                            doubleValue: recommendedUnits
                                        ),
                                        carbAmount: LoopQuantity(
                                            unit: .gram,
                                            doubleValue: carbEntry.amount
                                        ),
                                        emoji: carbEntry.foodType ?? ""
                                    ),
                                    programmedAmount: LoopQuantity(
                                        unit: .internationalUnit,
                                        doubleValue: decision?.manualBolusRequested ?? 0
                                    ),
                                    deliveryAmount: LoopQuantity(
                                        unit: .internationalUnit,
                                        doubleValue: dose.deliveredUnits ?? dose.programmedUnits
                                    )
                                ),
                                dose
                            ),
                            date: dose.startDate
                        )
                    )
                } else {
                    events.append(
                        InsulinDeliveryLogEvent(
                            id: decision?.syncIdentifier.uuidString ?? UUID().uuidString,
                            type: .pumpEvent(
                                .bolus(
                                    .correction(
                                        recommendedAmount: LoopQuantity(
                                            unit: .internationalUnit,
                                            doubleValue: recommendedUnits
                                        )
                                    ),
                                    programmedAmount: LoopQuantity(
                                        unit: .internationalUnit,
                                        doubleValue: decision?.manualBolusRequested ?? 0
                                    ),
                                    deliveryAmount: LoopQuantity(
                                        unit: .internationalUnit,
                                        doubleValue: dose.deliveredUnits ?? dose.programmedUnits
                                    )
                                ),
                                dose
                            ),
                            date: dose.startDate
                        )
                    )
                }
            } else {
                events.append(
                    InsulinDeliveryLogEvent(
                        id: dose.syncIdentifier ?? UUID().uuidString,
                        type: .pumpEvent(
                            .bolus(
                                .correction(recommendedAmount: nil),
                                programmedAmount: LoopQuantity(
                                    unit: .internationalUnit,
                                    doubleValue: dose.programmedUnits
                                ),
                                deliveryAmount: LoopQuantity(
                                    unit: .internationalUnit,
                                    doubleValue: dose.deliveredUnits ?? dose.programmedUnits
                                )
                            ),
                            dose
                        ),
                        date: dose.startDate
                    )
                )
            }
        }
    }
    
    private func handleDoseEvents(doses: [DoseEntry], decisions: [LightDosingDecision], fetchedDate: Date, events: inout [InsulinDeliveryLogEvent]) {
        let isPumpSuspended: Bool = {
            if case .suspended = pumpManager.status.basalDeliveryState {
                return true
            }
            return false
        }()
        
        let latestSuspendStartDate = doses.last(where: { $0.type == .suspend })?.startDate

        for dose in doses {
            let decision = decisions.first(where: { $0.id == dose.decisionId })
            switch dose.type {
            case .basal, .tempBasal:
                handleBasalEvent(dose: dose, decision: decision, events: &events)
            case .bolus:
                handleBolusEvents(dose: dose, decision: decision, events: &events)
            case .resume, .suspend:
                let isActiveSuspension = isPumpSuspended && dose.type == .suspend && dose.startDate == latestSuspendStartDate
                handleSuspendResumeEvents(dose: dose, fetchedDate: fetchedDate, isActiveSuspension: isActiveSuspension, events: &events)
            }
        }
    }

    private func handleSuspendResumeEvents(dose: DoseEntry, fetchedDate: Date, isActiveSuspension: Bool, events: inout [InsulinDeliveryLogEvent]) {
        guard dose.type == .suspend else { return }

        events.append(InsulinDeliveryLogEvent(id: dose.syncIdentifier ?? UUID().uuidString, type: .pumpEvent(.insulin(.suspended), dose), date: dose.startDate))

        if !isActiveSuspension && (!dose.isMutable || dose.endDate <= fetchedDate) {
            events.append(InsulinDeliveryLogEvent(id: dose.syncIdentifier ?? UUID().uuidString, type: .pumpEvent(.insulin(.resumed), dose), date: dose.endDate))
        }
    }
    
    private func handleAutomationEvents(_ events: inout [InsulinDeliveryLogEvent]) {
        loopDataManager.automationHistory.forEach { event in
            if event.enabled {
                events.append(InsulinDeliveryLogEvent(id: String(event.hashValue), type: .automation(.on), date: event.startDate))
            } else {
                events.append(InsulinDeliveryLogEvent(id: String(event.hashValue), type: .automation(.off(endDate: nil)), date: event.startDate))
            }
        }
    }
    
    private func handlePresetEvents(startDate: Date, _ events: inout [InsulinDeliveryLogEvent]) {
        loopDataManager.temporaryPresetsManager.presetHistory.recentEvents.filter({ $0.override.actualEndDate >= startDate }).forEach { event in
            if let preset = loopDataManager.temporaryPresetsManager.selectablePresets.first(where: { $0.id == event.override.presetId }) {
                events.append(InsulinDeliveryLogEvent(id: String(event.hashValue), type: .preset(.enabled, icon: preset.icon, name: preset.name), date: event.override.startDate))
                
                if event.override.hasFinished() {
                    events.append(InsulinDeliveryLogEvent(id: String(event.hashValue), type: .preset(.disabled, icon: preset.icon, name: preset.name), date: event.override.actualEndDate))
                }
            }
        }
    }
}
