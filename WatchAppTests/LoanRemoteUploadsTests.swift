//
//  LoanRemoteUploadsTests.swift
//  WatchAppTests
//
//  The phone's shared Nightscout configuration on the wrist: a grant without it keeps what is
//  staged, and the pump's teardown drops it with the loan.
//

import XCTest
import LoopKit
import LoopCore
import LoopAlgorithm
import NightscoutServiceKit
@testable import WatchApp

final class LoanRemoteUploadsTests: XCTestCase {

    private let nightscout = SharedDeviceConfiguration(managerIdentifier: "NightscoutService", asOf: Date(),
                                                       state: ["siteURL": "https://fixture-site.example", "apiSecret": "fixture-secret"])

    override func tearDown() {
        LoanRemoteUploads.shared.end()
        super.tearDown()
    }

    /// A later grant without credentials (a seize from the standing copy, an older phone) must
    /// not switch uploads off; only the loan's end does.
    func testACredentialLessGrantKeepsStagedCredentials() {
        let uploads = LoanRemoteUploads()
        XCTAssertFalse(uploads.holdsServiceConfigurations)

        uploads.stage(services: [nightscout], phoneCGMUploadsGlucose: true)
        uploads.stage(services: [], phoneCGMUploadsGlucose: nil)
        XCTAssertTrue(uploads.holdsServiceConfigurations, "a credential-less grant cleared the staged credentials")

        uploads.end()
        XCTAssertFalse(uploads.holdsServiceConfigurations, "the loan's end left credentials behind")
    }

    /// Every way a loan ends runs through the pump's teardown; the credentials go with it.
    /// Without its own CGM the watch follows the phone's CGM (the simulator's "Upload CGM Samples"),
    /// carried in the grant; a phone that sends no answer gets stock's yes.
    func testWithoutItsOwnCGMTheWatchFollowsThePhonesGlucoseUploadSetting() {
        for answer in [false, true] {
            let uploads = LoanRemoteUploads()
            uploads.stage(services: [nightscout], phoneCGMUploadsGlucose: answer)
            XCTAssertEqual(uploads.shouldSyncGlucoseToRemoteService, answer)
        }
        let older = LoanRemoteUploads()
        older.stage(services: [nightscout], phoneCGMUploadsGlucose: nil)
        XCTAssertTrue(older.shouldSyncGlucoseToRemoteService)
    }

    /// The phone's service exports its site and secret; the wrist's, built from that export,
    /// uploads to the same site, says it was configured elsewhere, and refuses an incomplete export.
    func testTheWristAdoptsThePhonesNightscoutService() throws {
        let phone = NightscoutService()
        phone.siteURL = URL(string: "https://fixture-site.example")
        phone.apiSecret = "fixture-secret"

        let wrist = try XCTUnwrap(NightscoutService(adopting: phone.exportConfiguration(), localState: nil))
        XCTAssertEqual(wrist.siteURL, phone.siteURL)
        XCTAssertEqual(wrist.apiSecret, phone.apiSecret)
        XCTAssertTrue(wrist.isOnboarded)
        XCTAssertTrue(wrist.isConfiguredByAnotherController)
        XCTAssertFalse(phone.isConfiguredByAnotherController)

        XCTAssertNil(NightscoutService(adopting: NightscoutService().exportConfiguration(), localState: nil), "no secret")
    }

    /// With no service running there is nothing to confirm, and the answer comes at once.
    func testWithNoServiceRunningNothingIsConfirmed() {
        var answer: [String: [String]]?
        LoanRemoteUploads().confirmUploads(within: 5) { answer = $0 }
        XCTAssertEqual(answer, [:])
    }

    func testPumpTeardownEndsUploads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cacheStore = PersistenceController(directoryURL: directory.appendingPathComponent("cache"))
        let doseStore = await DoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                        longestEffectDuration: ExponentialInsulinModelPreset.rapidActingAdult.effectDuration,
                                        provenanceIdentifier: "LoanRemoteUploadsTests")
        let glucoseStore = await GlucoseStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                              cacheLength: .hours(4), provenanceIdentifier: "LoanRemoteUploadsTests")
        let carbStore = CarbStore(healthKitSampleStore: nil, cacheStore: cacheStore,
                                  cacheLength: .hours(24), provenanceIdentifier: "LoanRemoteUploadsTests")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LoanRemoteUploadsTests-\(UUID().uuidString)"))
        let manager = WatchLoopManager(doseStore: doseStore, glucoseStore: glucoseStore, carbStore: carbStore,
                                       defaults: defaults, stateDirectory: directory)
        let controller = PodLoanWatchController(loopManager: manager,
                                                journal: LoanEventJournal(directory: directory),
                                                stateDirectory: directory)

        LoanRemoteUploads.shared.stage(services: [nightscout], phoneCGMUploadsGlucose: true)
        XCTAssertTrue(LoanRemoteUploads.shared.holdsServiceConfigurations)

        controller.queue.sync { controller.teardownPump() }
        XCTAssertFalse(LoanRemoteUploads.shared.holdsServiceConfigurations, "uploads outlived the pump's teardown")
    }

    /// Only a background request on cellular alone is held: watchOS refuses it cellular and it waits.
    /// In front, during a workout, over Wi-Fi or the phone link, or with the route not yet known, it goes.
    func testTheUploadGateHoldsOnlyBackgroundCellular() {
        typealias U = LoanRemoteUploads
        XCTAssertFalse(U.mayUpload(inFront: false, workoutRunning: false, route: .cellularOnly))
        XCTAssertTrue(U.mayUpload(inFront: true, workoutRunning: false, route: .cellularOnly))
        XCTAssertTrue(U.mayUpload(inFront: false, workoutRunning: true, route: .cellularOnly))
        XCTAssertTrue(U.mayUpload(inFront: false, workoutRunning: false, route: .other))
        XCTAssertTrue(U.mayUpload(inFront: false, workoutRunning: false, route: .unknown))
    }
}
