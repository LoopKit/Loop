//
//  LoanRemoteUploads.swift
//  WatchApp
//
//  Uploads from the wrist while it holds the pod. Stock's RemoteDataServicesManager, compiled
//  into this target unchanged, drives services adopted from the configurations the Start grant
//  carried. Its triggers are the store delegates stock's DeviceDataManager uses on the phone.
//
//  This file persists no credential. The loan's saved state keeps the grant's configurations
//  beside the pump's own state, so a relaunch mid-loan stages them again; both go at teardown.
//  Credentials are never logged. The query anchors are stock's, in this app's defaults, so a
//  later loan carries on from where the last one stopped.
//

import Foundation
import LoopKit
import Network
import WatchKit
import LoopAlgorithm
import LoopCore
import NightscoutServiceKit
import TidepoolServiceKit

/// Stock declares this in DeviceDataManager.swift, which the watch does not compile.
protocol UploadEventListener {
    func triggerUpload(for triggeringType: RemoteDataType)
}

final class LoanRemoteUploads {
    static let shared = LoanRemoteUploads()

    private let lock = UnfairLock()

    /// The services the wrist can adopt from the phone's shared configurations.
    private static let adoptable: [DeviceConfigurationSharing.Type] = [NightscoutService.self, TidepoolService.self]

    /// From accepted grants, by plugin identifier; consumed when each service starts. Cleared only by `end`.
    private var staged: [String: SharedDeviceConfiguration] = [:]

    /// The phone's CGM's answer to "upload glucose?", from the grant. Cleared by `end`.
    private var phoneUploadsGlucose: Bool?

    /// Set while the loan is ACTIVE; credentials staged then start the service at once.
    private weak var activeLoop: WatchLoopManager?

    private var manager: RemoteDataServicesManager?
    private var running: [RemoteDataService] = []

    /// Bumped by `end`, so a start still waiting for main does not outlive its loan.
    private var generation = 0

    /// Stock's manager wants a CGM event store; the wrist records none, so this one stays empty.
    private static let emptyCgmEventStore: LoopKit.CgmEventStore? = {
        guard let documents = try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return nil }
        let cacheStore = LoopKit.PersistenceController(directoryURL: documents.appendingPathComponent("LoanUploadsCgmEvents"), isReadOnly: false)
        return LoopKit.CgmEventStore(cacheStore: cacheStore)
    }()

    /// The wrist's route to the internet, logged at each change once uploads first start. Uploads
    /// wait for one, so this says why they waited.
    private let pathMonitor = NWPathMonitor()
    private var pathLogStarted = false

    /// The route the wrist last reported, for the gate; `.unknown` until the monitor first reports.
    private var route: Route = .unknown
    /// Types whose upload was held because it could not succeed yet; sent when the way opens.
    private var held: Set<RemoteDataType> = []

    enum Route { case unknown, cellularOnly, other }

    init() {}

    /// Configurations are staged or a running service holds them. For tests; says nothing of their values.
    var holdsServiceConfigurations: Bool {
        lock.withLock { !staged.isEmpty || !running.isEmpty }
    }

    /// Called on grant acceptance with the phone's shared service configurations. A grant without
    /// them never clears what is already staged (only `end` does); one arriving while the loan is
    /// ACTIVE starts at once.
    func stage(services: [SharedDeviceConfiguration], phoneCGMUploadsGlucose: Bool?) {
        let active = lock.withLock { () -> WatchLoopManager? in
            if !services.isEmpty {
                services.forEach { staged[$0.managerIdentifier] = $0 }
                phoneUploadsGlucose = phoneCGMUploadsGlucose
            }
            return activeLoop
        }
        SportLog.event("uploads", "grant: service configuration(s) \(services.isEmpty ? "absent (staged kept)" : services.map(\.managerIdentifier).joined(separator: ", "))")
        if let active { startStaged(loopManager: active) }
    }

    /// Loan ACTIVE: start whatever is staged; a later grant can still bring credentials.
    func begin(loopManager: WatchLoopManager) {
        lock.withLock { activeLoop = loopManager }
        startStaged(loopManager: loopManager)
    }

    private func startStaged(loopManager: WatchLoopManager) {
        let (configurations, anyRunning, beganIn) = lock.withLock { () -> ([SharedDeviceConfiguration], Bool, Int) in
            let started = Set(running.map(\.pluginIdentifier))
            let pending = staged.values.filter { !started.contains($0.managerIdentifier) }
            staged = [:]
            return (pending, !running.isEmpty, generation)
        }
        guard !configurations.isEmpty else {
            if !anyRunning {
                SportLog.event("uploads", "loan active, no service configuration yet — uploads start if a grant brings one")
            }
            return
        }

        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                guard let manager = managerForLoan(loopManager, beganIn: beganIn) else { return }
                configurations.forEach { start($0, manager: manager, beganIn: beganIn) }
            }
        }
    }

    /// One stock manager per loan, with stock's store-delegate triggers.
    @MainActor
    private func managerForLoan(_ loopManager: WatchLoopManager, beganIn: Int) -> RemoteDataServicesManager? {
        if let existing = lock.withLock({ self.generation == beganIn ? self.manager : nil }) { return existing }
        guard let alertStore = loopManager.alertStore,
              let dosingDecisionStore = loopManager.dosingDecisionStore,
              let deviceLog = loopManager.deviceLog,
              let emptyCgmEventStore = LoanRemoteUploads.emptyCgmEventStore else {
            SportLog.event("uploads", "a store is missing — uploads OFF for this loan")
            return nil
        }
        let manager = RemoteDataServicesManager(
            alertStore: alertStore,
            carbStore: loopManager.carbStore,
            doseStore: loopManager.doseStore,
            dosingDecisionStore: dosingDecisionStore,
            glucoseStore: loopManager.glucoseStore,
            cgmEventStore: emptyCgmEventStore,
            settingsProvider: loopManager.settingsProvider,
            overrideHistory: loopManager.overrideHistory,
            insulinDeliveryStore: loopManager.doseStore.insulinDeliveryStore,
            deviceLog: deviceLog,
            automationHistoryProvider: self
        )
        manager.delegate = self
        let current = lock.withLock { () -> Bool in
            guard generation == beganIn else { return false }
            self.manager = manager
            return true
        }
        guard current else {
            SportLog.event("uploads", "loan ended before uploads started — not starting")
            return nil
        }

        // Stock's DeviceDataManager wiring. The dose store's delegate stays WatchLoopManager,
        // which forwards pump events here.
        alertStore.delegate = self
        loopManager.carbStore.delegate = self
        loopManager.glucoseStore.delegate = self
        dosingDecisionStore.delegate = self
        loopManager.doseStore.insulinDeliveryStore.delegate = self
        return manager
    }

    @MainActor
    private func start(_ configuration: SharedDeviceConfiguration, manager: RemoteDataServicesManager, beganIn: Int) {
        let adopted = Self.adoptable.lazy.compactMap { $0.init(adopting: configuration, localState: nil) as? RemoteDataService }.first
        guard let service = adopted else {
            SportLog.event("uploads", "the phone's \(configuration.managerIdentifier) configuration could not be adopted — its uploads OFF for this loan")
            return
        }
        guard lock.withLock({ () -> Bool in
            guard generation == beganIn else { return false }
            running.append(service)
            return true
        }) else { return }
        startPathLog()
        // As stock's addService: everything past the saved anchors goes up now.
        manager.addService(service)
        SportLog.event("uploads", "uploads ON — stock RemoteDataServicesManager driving \(service.pluginIdentifier) (credentials not logged)")
    }

    /// Pump teardown or loan end. Synchronous, so nothing the teardown writes afterwards is
    /// uploaded; idempotent.
    func end() {
        let (services, loopManager) = lock.withLock { () -> ([RemoteDataService], WatchLoopManager?) in
            defer {
                manager = nil; running = []; staged = [:]; activeLoop = nil; phoneUploadsGlucose = nil; held = []
                generation += 1
            }
            return (running, activeLoop)
        }

        // An upload already under way finds no credentials and returns. Tidepool's session is only
        // dropped here, never logged out: that would end the phone's. Dropping it calls Tidepool's
        // "reauthenticate" alert, which goes nowhere: the wrist never sets a serviceDelegate.
        for service in services {
            if let nightscout = service as? NightscoutService {
                nightscout.siteURL = nil
                nightscout.apiSecret = nil
            }
            if let tidepool = service as? TidepoolService {
                Task { await tidepool.tapi.setSession(nil) }
            }
            SportLog.event("uploads", "uploads OFF — loan over, \(service.pluginIdentifier) dropped")
        }
        if let loopManager {
            loopManager.alertStore?.delegate = nil
            loopManager.carbStore.delegate = nil
            loopManager.glucoseStore.delegate = nil
            loopManager.dosingDecisionStore?.delegate = nil
            loopManager.doseStore.insulinDeliveryStore.delegate = nil
        }
    }

    /// The hand-back is starting: everything not yet uploaded goes now.
    func flush() {
        guard let manager = lock.withLock({ self.manager }) else { return }
        Task { @MainActor in manager.triggerAllUploads() }
    }

    /// The types the phone would otherwise upload a second copy of, confirmed per service when the
    /// store holds nothing past the service's upload bookmark; waits up to `within` for a flush to
    /// land. Empty with no service running, at once.
    func confirmUploads(within: TimeInterval, completion: @escaping ([String: [String]]) -> Void) {
        let (services, loop) = lock.withLock { (running, activeLoop) }
        guard !services.isEmpty, let loop else { return completion([:]) }
        Task {
            let deadline = Date().addingTimeInterval(within)
            var confirmed: [String: [String]] = [:]
            repeat {
                for service in services {
                    confirmed[service.pluginIdentifier] = await Self.typesUploaded(to: service, from: loop)
                }
                if confirmed.values.allSatisfy({ $0.count == 2 }) { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            } while Date() < deadline
            completion(confirmed.filter { !$0.value.isEmpty })
        }
    }

    private static func typesUploaded(to service: RemoteDataService, from loop: WatchLoopManager) async -> [String] {
        var types: [String] = []
        let glucoseAnchor: GlucoseStore.QueryAnchor? = UserDefaults.appGroup?.getQueryAnchor(for: service, withRemoteDataType: .glucose)
        if let pending = try? await loop.glucoseStore.executeGlucoseQuery(fromQueryAnchor: glucoseAnchor ?? GlucoseStore.QueryAnchor(), limit: 1).1,
           pending.isEmpty {
            types.append(RemoteDataType.glucose.rawValue)
        }
        if let store = loop.dosingDecisionStore {
            let anchor: DosingDecisionStore.QueryAnchor? = UserDefaults.appGroup?.getQueryAnchor(for: service, withRemoteDataType: .dosingDecision)
            let pending: [StoredDosingDecision]? = await withCheckedContinuation { continuation in
                store.executeDosingDecisionQuery(fromQueryAnchor: anchor, limit: 1) { result in
                    if case .success(_, let decisions) = result { continuation.resume(returning: decisions) } else { continuation.resume(returning: nil) }
                }
            }
            if pending?.isEmpty == true { types.append(RemoteDataType.dosingDecision.rawValue) }
        }
        return types
    }

    /// Whether a request made now can go out. watchOS refuses cellular to a backgrounded app's
    /// requests ("Interface type 'cellular' is prohibited by parameters") and leaves them waiting until a
    /// timeout or a route change; the phone link and Wi-Fi are allowed in the background, and a running
    /// workout lifts the refusal. An unknown route never holds.
    static func mayUpload(inFront: Bool, workoutRunning: Bool, route: Route) -> Bool {
        inFront || workoutRunning || route != .cellularOnly
    }

    /// Every type goes up now, held or not: what a relaunch forgot, and what stock's own catch-up
    /// left waiting in the background, both resume from stock's anchors. Free in front.
    func releaseAll(reason: String) {
        guard lock.withLock({ () -> Bool in held = []; return manager != nil }) else { return }
        SportLog.event("uploads", "sending every upload type — \(reason)")
        flush()
    }

    /// Held types go up now, through the gate again (it decides with the current state).
    func releaseHeld(reason: String) {
        let types = lock.withLock { () -> Set<RemoteDataType> in defer { held = [] }; return held }
        guard !types.isEmpty else { return }
        SportLog.event("uploads", "releasing \(types.count) held upload type(s) — \(reason)")
        types.forEach { trigger($0) }
    }

    /// Stock's trigger, through its own awaitable variant so each outcome reaches this log; stock
    /// reports a failure only to the system log. Held instead while it could only wait (see `mayUpload`).
    func trigger(_ type: RemoteDataType) {
        guard let manager = lock.withLock({ self.manager }) else { return }
        Task { @MainActor in
            let inFront = WKApplication.shared().applicationState != .background
            let workout = ExtensionDelegate.sharedIfAvailable()?.stockLoopSession?.workoutRunning ?? false
            let route = lock.withLock { self.route }
            guard Self.mayUpload(inFront: inFront, workoutRunning: workout, route: route) else {
                let first = lock.withLock { () -> Bool in held.insert(type).inserted }
                if first {
                    SportLog.event("uploads", "\(type.rawValue) upload HELD — in the background on cellular only, where it could only wait; it goes when the app opens or the route changes")
                }
                return
            }
            let started = Date()
            await manager.performUpload(for: type)
            let failing = manager.failedUploads.map { "\($0.serviceIdentifier) \($0.remoteDataType.rawValue)" }.sorted()
            SportLog.event("uploads", "\(type.rawValue) upload settled in \(String(format: "%.1f", Date().timeIntervalSince(started))) s · failing: \(failing.isEmpty ? "none" : failing.joined(separator: ", "))")
        }
    }

    private func startPathLog() {
        guard lock.withLock({ () -> Bool in defer { pathLogStarted = true }; return !pathLogStarted }) else { return }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.availableInterfaces
            let newRoute: Route = !available.isEmpty && available.allSatisfy({ $0.type == .cellular }) ? .cellularOnly : .other
            if let self {
                let opened = self.lock.withLock { () -> Bool in
                    defer { self.route = newRoute }
                    return self.route == .cellularOnly && newRoute == .other
                }
                if opened { self.releaseHeld(reason: "route no longer cellular-only") }
            }
            let kinds: [(NWInterface.InterfaceType, String)] = [(.wifi, "Wi-Fi"), (.cellular, "cellular"), (.wiredEthernet, "wired"), (.other, "other")]
            let via = kinds.filter { path.usesInterfaceType($0.0) }.map(\.1)
            let interfaces = path.availableInterfaces.map(\.name).joined(separator: ",")
            SportLog.event("net", "internet path \(path.status) via \(via.isEmpty ? "nothing" : via.joined(separator: "+")) · interfaces [\(interfaces)]\(path.isExpensive ? " · expensive" : "")\(path.isConstrained ? " · constrained" : "")")
        }
        pathMonitor.start(queue: DispatchQueue(label: "LoanRemoteUploads.path", qos: .utility))
    }
}

// MARK: - Stock's store delegates (DeviceDataManager on the phone)

extension LoanRemoteUploads: AlertStoreDelegate {
    func alertStoreHasUpdatedAlertData(_ alertStore: AlertStore) { trigger(.alert) }
}

extension LoanRemoteUploads: CarbStoreDelegate {
    func carbStoreHasUpdatedCarbData(_ carbStore: CarbStore) { trigger(.carb) }
    func carbStore(_ carbStore: CarbStore, didError error: CarbStore.CarbStoreError) {}
}

extension LoanRemoteUploads: GlucoseStoreDelegate {
    func glucoseStoreHasUpdatedGlucoseData(_ glucoseStore: GlucoseStore) { trigger(.glucose) }
}

extension LoanRemoteUploads: DosingDecisionStoreDelegate {
    func dosingDecisionStoreHasUpdatedDosingDecisionData(_ dosingDecisionStore: DosingDecisionStore) { trigger(.dosingDecision) }
}

extension LoanRemoteUploads: InsulinDeliveryStoreDelegate {
    func insulinDeliveryStoreHasUpdatedDoseData(_ insulinDeliveryStore: InsulinDeliveryStore) { trigger(.dose) }
}

// MARK: - What stock's manager asks of its owner

extension LoanRemoteUploads: RemoteDataServicesManagerDelegate {
    /// As stock DeviceDataManager, the CGM manager decides. During a loan the watch is the only
    /// glucose uploader (the phone holds its own); with no CGM of its own it follows the phone's
    /// CGM, whose readings it holds (seeded and relayed). An older phone sends no answer: stock's yes.
    var shouldSyncGlucoseToRemoteService: Bool {
        let (loop, phone) = lock.withLock { (activeLoop, phoneUploadsGlucose) }
        return loop?.cgmManager?.shouldSyncToRemoteService ?? phone ?? true
    }
}

extension LoanRemoteUploads: AutomationHistoryProvider {
    /// The wrist keeps no automation history; the loan's current mode stands for the window.
    func automationHistory(from start: Date, to end: Date) async throws -> [AbsoluteScheduleValue<Bool>] {
        let enabled = lock.withLock { activeLoop }?.closedLoopEnabledNonBlocking ?? false
        return [AbsoluteScheduleValue(startDate: start, endDate: end, value: enabled)]
    }
}
