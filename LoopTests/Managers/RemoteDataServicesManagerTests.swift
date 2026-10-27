import XCTest
@testable import LoopKit
@testable import Loop

final class RemoteDataServicesManagerTests: XCTestCase {
    func testRestoreQueriesUnchangedDoseSettingsAndCarbStreamsWithoutAnotherEvent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Core Data can outlive these stores through queued work; leave its files in the
        // isolated test sandbox rather than unlinking an open SQLite database.
        let cache = PersistenceController(directoryURL: folder)
        let ready = expectation(description: "source cache ready")
        cache.onReady { error in XCTAssertNil(error); ready.fulfill() }
        wait(for: [ready], timeout: 5)
        let carbStore = CarbStore(cacheStore: cache, cacheLength: 86400,
            defaultAbsorptionTimes: (fast: 1800, medium: 10800, slow: 18000), provenanceIdentifier: "offline")
        let doseStore = DoseStore(cacheStore: cache, insulinModelProvider: PresetInsulinModelProvider(defaultRapidActingModel: ExponentialInsulinModelPreset.rapidActingAdult),
            longestEffectDuration: 21600, basalProfile: nil, insulinSensitivitySchedule: nil, provenanceIdentifier: "offline")
        let manager = RemoteDataServicesManager(alertStore: AlertStore(), carbStore: carbStore, doseStore: doseStore,
            dosingDecisionStore: DosingDecisionStore(store: cache, expireAfter: 86400),
            glucoseStore: GlucoseStore(cacheStore: cache, provenanceIdentifier: "offline"),
            cgmEventStore: CgmEventStore(cacheStore: cache), settingsStore: SettingsStore(store: cache, expireAfter: 86400),
            overrideHistory: TemporaryScheduleOverrideHistory(), insulinDeliveryStore: doseStore.insulinDeliveryStore)
        let doses = expectation(description: "dose drain"), settings = expectation(description: "settings drain"), carbs = expectation(description: "carb drain")
        let service = RestoreQueryService { kind in
            switch kind { case "dose": doses.fulfill(); case "settings": settings.fulfill(); case "carb": carbs.fulfill(); default: break }
        }
        manager.restoreService(service)
        wait(for: [doses, settings, carbs], timeout: 5)
        let completed = expectation(description: "all restoration queries complete")
        manager.uploadGroup.notify(queue: .main) { completed.fulfill() }
        wait(for: [completed], timeout: 5)
        manager.removeService(service)
    }
}

private final class RestoreQueryService: RemoteDataService {
    static let pluginIdentifier = "RestoreQueryTest-\(UUID().uuidString)"
    static let localizedTitle = "Restoration test"
    weak var serviceDelegate: ServiceDelegate?
    weak var stateDelegate: StatefulPluggableDelegate?
    var rawState: RawStateValue { [:] }
    var isOnboarded: Bool { true }
    private let drained: (String) -> Void
    init(_ drained: @escaping (String) -> Void) { self.drained = drained }
    init?(rawState: RawStateValue) { drained = { _ in } }
    func uploadDoseData(created: [DoseEntry], deleted: [DoseEntry], completion: @escaping (Result<Bool, Error>) -> Void) {
        XCTAssertTrue(created.isEmpty && deleted.isEmpty); drained("dose"); completion(.success(true))
    }
    func uploadSettingsData(_ stored: [StoredSettings], completion: @escaping (Result<Bool, Error>) -> Void) {
        XCTAssertTrue(stored.isEmpty); drained("settings"); completion(.success(true))
    }
    func uploadCarbData(created: [SyncCarbObject], updated: [SyncCarbObject], deleted: [SyncCarbObject], completion: @escaping (Result<Bool, Error>) -> Void) {
        XCTAssertTrue(created.isEmpty && updated.isEmpty && deleted.isEmpty); drained("carb"); completion(.success(true))
    }
    func uploadAlertData(_ stored: [SyncAlertObject], completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }
    func uploadTemporaryOverrideData(updated: [TemporaryScheduleOverride], deleted: [TemporaryScheduleOverride], completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }
    func uploadDosingDecisionData(_ stored: [StoredDosingDecision], completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }
    func uploadGlucoseData(_ stored: [StoredGlucoseSample], completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }
    func uploadPumpEventData(_ stored: [PersistedPumpEvent], completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }
    func uploadCgmEventData(_ stored: [PersistedCgmEvent], completion: @escaping (Result<Bool, Error>) -> Void) { completion(.success(true)) }
    func remoteNotificationWasReceived(_ notification: [String: AnyObject]) async throws {}
}
