//
//  LoanProtocolV2Tests.swift
//  LoopTests
//
//  Loan protocol v2: wire round-trips and version skew, the pulse-accurate expected-insulin
//  model, the reconciler's reroute through addPumpEvents, and dose identity.
//

import XCTest
import HealthKit
import LoopKit
import LoopCore
import LoopAlgorithm
@testable import Loop

final class LoanProtocolV2Tests: XCTestCase {

    // MARK: - Wire format

    private func roundTrip(_ message: LoanMessage) throws -> LoanMessage? {
        let dict = try message.transportDictionary()
        return try LoanMessage.decode(fromTransport: dict)
    }

    func testEveryMessageKindRoundTrips() throws {
        // Dates on the wire's millisecond grid: the protocol encodes Int64 ms, so
        // sub-millisecond fractions deliberately do not survive (determinism > ULPs).
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let status = LoanPodStatus(timestamp: now, deliveredUnits: 12.3, reservoirLevel: nil, isSuspended: false, faultCode: nil)
        let event = LoanEvent(id: UUID(), seq: 3, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: now, amount: 1.0), loggedAt: now)
        let messages: [LoanMessage] = [
            .request(LoanRequest(watchBuild: "77")),
            .grant(LoanGrant(epoch: 5, expiresAt: now.addingTimeInterval(300),
                             pumpConfiguration: Data([1, 2, 3]), podAddress: 0x1F0A2B3C,
                             therapySettingsRaw: Data([4, 5]), settingsTimeZoneID: "America/New_York",
                             doseHistory: [LoanDoseRecord(kind: .tempBasal, startDate: now, endDate: now.addingTimeInterval(1800), unitsPerHour: 0.8)])),
            .takeoverComplete(TakeoverComplete(epoch: 5, firstPodStatus: status)),
            .takeoverFailed(TakeoverFailed(epoch: 5, reason: "test")),
            .doseRecordBatch(DoseRecordBatch(epoch: 5, events: [event], tombstones: [UUID()])),
            .handbackOffer(HandbackOffer(epoch: 5, handedBackAt: now, finalStatus: status,
                                         odometer: LoanOdometerSnapshot(deliveredAtStart: 10, deliveredLatest: 12, freshenSucceeded: true),
                                         events: [event], tombstones: [], recovered: false)),
            .handbackAck(HandbackAck(epoch: 5, committedCursor: 3)),
            .revoke(Revoke(epoch: 5)),
            .statusQuery(StatusQuery(epoch: 5)),
            .statusReport(StatusReport(epoch: 5, mode: .closedDirect, lastDirectGlucoseAge: 120, lastEventSeq: 3, podFault: nil, holdsPod: true)),
            .nack(ProtocolNack(seenVersion: 1)),
            .denied(LoanDenied(reason: "settings incomplete")),
            .diag(LoanDiag(epoch: 5, text: "offer RX ev=3")),
        ]
        for message in messages {
            XCTAssertEqual(try roundTrip(message), message)
        }
    }

    func testGrantCarbHistoryRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let carb = LoanCarbRecord(syncIdentifier: "carb-abc", provenanceIdentifier: "com.loopkit.Loop",
                                  syncVersion: 1, startDate: now, grams: 25, absorptionTime: .hours(3),
                                  foodType: "🍕", userCreatedDate: now, userUpdatedDate: nil)
        let grant = LoanGrant(epoch: 7, expiresAt: now.addingTimeInterval(300),
                              pumpConfiguration: Data([1]), podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                              doseHistory: [], carbHistory: [carb])
        guard case .grant(let g) = try roundTrip(.grant(grant)) else { return XCTFail("not a grant") }
        XCTAssertEqual(g.carbHistory, [carb], "carb history must survive the wire")

        // Backward compat: an older phone sends no carbHistory; it must decode as nil, not [].
        let old = LoanGrant(epoch: 7, expiresAt: now.addingTimeInterval(300),
                            pumpConfiguration: Data([1]), podAddress: 0,
                            therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                            doseHistory: [])
        guard case .grant(let g2) = try roundTrip(.grant(old)) else { return XCTFail("not a grant") }
        XCTAssertNil(g2.carbHistory)
    }

    func testGrantGlucoseHistoryRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let sample = LoanGlucoseRecord(syncIdentifier: "g-1", startDate: now, valueMgdl: 120,
                                       trendRateMgdlPerMin: 1.5, isDisplayOnly: false, wasUserEntered: false)
        let grant = LoanGrant(epoch: 8, expiresAt: now.addingTimeInterval(300),
                              pumpConfiguration: Data([1]), podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                              doseHistory: [], glucoseHistory: [sample])
        guard case .grant(let g) = try roundTrip(.grant(grant)) else { return XCTFail("not a grant") }
        XCTAssertEqual(g.glucoseHistory, [sample], "glucose history must survive the wire")

        // Backward compat: an older phone sends no glucoseHistory; it must decode as nil, not [].
        let old = LoanGrant(epoch: 8, expiresAt: now.addingTimeInterval(300),
                            pumpConfiguration: Data([1]), podAddress: 0,
                            therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                            doseHistory: [])
        guard case .grant(let g2) = try roundTrip(.grant(old)) else { return XCTFail("not a grant") }
        XCTAssertNil(g2.glucoseHistory)
    }

    /// A service's shared configuration (its site and secret) survives the wire, and no textual or
    /// reflected form of the grant shows it; a grant from an older phone decodes with none.
    func testGrantServiceConfigurationsRoundTripRedacted() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let secret = "fixture-secret-0123456789"
        let shared = SharedDeviceConfiguration(managerIdentifier: "NightscoutService", asOf: now,
                                               state: ["siteURL": "https://fixture-site.example", "apiSecret": secret])
        var grant = LoanGrant(epoch: 9, expiresAt: now.addingTimeInterval(300),
                              pumpConfiguration: Data([1]), podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                              doseHistory: [])
        grant.serviceConfigurations = [try XCTUnwrap(shared.propertyList)]
        grant.phoneCGMUploadsGlucose = false
        guard case .grant(let g) = try roundTrip(.grant(grant)) else { return XCTFail("not a grant") }
        let decoded = try XCTUnwrap(g.sharedServiceConfigurations.first)
        XCTAssertEqual(decoded.managerIdentifier, "NightscoutService")
        XCTAssertEqual(decoded.state["apiSecret"] as? String, secret)
        XCTAssertEqual(g.phoneCGMUploadsGlucose, false)

        var dumped = ""
        dump(grant, to: &dumped)
        for text in [String(describing: grant), String(reflecting: grant), dumped] {
            XCTAssertFalse(text.contains(secret), "the secret leaked")
            XCTAssertFalse(text.contains("fixture-site"), "the site leaked")
        }

        let old = LoanGrant(epoch: 9, expiresAt: now.addingTimeInterval(300),
                            pumpConfiguration: Data([1]), podAddress: 0,
                            therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC",
                            doseHistory: [])
        guard case .grant(let g2) = try roundTrip(.grant(old)) else { return XCTFail("not a grant") }
        XCTAssertTrue(g2.sharedServiceConfigurations.isEmpty)
        XCTAssertNil(g2.phoneCGMUploadsGlucose)
    }

    /// The watch's upload confirmation survives the wire on the released offer and the loan history;
    /// an older watch sends neither.
    func testUploadConfirmationRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let confirmed = ["NightscoutService": ["Glucose", "DosingDecision"]]
        let offer = HandbackOffer(epoch: 4, handedBackAt: now, finalStatus: nil, odometer: nil, events: [], tombstones: [],
                                  recovered: false, released: true, uploadsConfirmed: confirmed)
        guard case .handbackOffer(let o) = try roundTrip(.handbackOffer(offer)) else { return XCTFail("not an offer") }
        XCTAssertEqual(o.uploadsConfirmed, confirmed)
        XCTAssertEqual(o.servicesConfirming("Glucose"), ["NightscoutService"])

        let older = HandbackOffer(epoch: 4, handedBackAt: now, finalStatus: nil, odometer: nil, events: [], tombstones: [],
                                  recovered: false, released: true)
        guard case .handbackOffer(let o2) = try roundTrip(.handbackOffer(older)) else { return XCTFail("not an offer") }
        XCTAssertNil(o2.uploadsConfirmed)
        XCTAssertEqual(o2.servicesConfirming("Glucose"), [])

        let history = LoanHistory(epoch: 4, decisions: [], uploadsConfirmed: confirmed)
        let decoded = try PropertyListDecoder().decode(LoanHistory.self, from: try history.encoded())
        XCTAssertEqual(decoded.servicesConfirming("DosingDecision"), ["NightscoutService"])
    }

    /// The grant seeds the algorithm's 12 h glucose window: every five minutes, with identifiers as
    /// long as a UUID, it fits inside the 60 KB urgent limit.
    func testTwelveHoursOfGlucoseStaySmallInTheGrant() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000.125)
        let readings = (0...144).map { i in
            LoanGlucoseRecord(syncIdentifier: UUID().uuidString, startDate: now.addingTimeInterval(Double(-i) * 300),
                              valueMgdl: 120, trendRateMgdlPerMin: 1.5, isDisplayOnly: false, wasUserEntered: false)
        }
        func grant(_ glucose: [LoanGlucoseRecord]?) -> LoanGrant {
            LoanGrant(epoch: 8, expiresAt: now.addingTimeInterval(300), pumpConfiguration: Data([1]), podAddress: 0,
                      therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC", doseHistory: [], glucoseHistory: glucose)
        }
        let with = try LoanProtocol.encoder.encode(LoanEnvelope(message: .grant(grant(readings)))).count
        let without = try LoanProtocol.encoder.encode(LoanEnvelope(message: .grant(grant(nil)))).count
        print("GLUCOSE-SEED-SIZE grant +\(with - without)B for \(readings.count) readings")
        // About 25 KB: with a typical day's doses the grant lands near 50 KB of the 60 KB urgent limit.
        XCTAssertLessThan(with - without, 30_000, "12 h of glucose leaves the grant inside the 60 KB urgent limit")
    }

    /// The grant carries the pump's exported configuration whole; the watch reads only its header.
    func testGrantCarriesThePumpsSharedConfiguration() throws {
        let asOf = Date(timeIntervalSince1970: 1_784_338_000)
        let configuration = SharedDeviceConfiguration(managerIdentifier: "Pump", asOf: asOf, deliveredUnits: 41.25,
                                                      state: ["opaque": ["nested": Data([9])]])
        let data = try PropertyListSerialization.data(fromPropertyList: configuration.rawValue, format: .binary, options: 0)
        let grant = LoanGrant(epoch: 4, expiresAt: asOf.addingTimeInterval(300), pumpConfiguration: data, podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC", doseHistory: [])
        guard case .grant(let received) = try roundTrip(.grant(grant)) else { return XCTFail("not a grant") }

        let decoded = try XCTUnwrap(received.sharedPumpConfiguration)
        XCTAssertEqual(decoded.managerIdentifier, "Pump")
        XCTAssertEqual(decoded.asOf, asOf)
        XCTAssertEqual(decoded.deliveredUnits, 41.25)
        XCTAssertEqual((decoded.state["opaque"] as? [String: Any])?["nested"] as? Data, Data([9]))
    }

    /// The glucose alert settings ride the grant; a grant from an older phone has none.
    func testGrantGlucoseAlertSettingsRoundTripAndAreOptional() throws {
        var profile = GlucoseAlertProfile.makePrimary()
        profile.configuration.lowThresholdMgDL = 75
        let settings = GlucoseAlertSettings(profiles: [profile], activeProfileID: profile.id,
                                            cgmProvidesOwnAlerts: false, loopAlertsOverrideForOwnAlertingCGM: false)
        let grant = LoanGrant(epoch: 4, expiresAt: Date(), pumpConfiguration: Data([1]), podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC", doseHistory: [],
                              glucoseAlertSettings: settings.encoded)
        guard case .grant(let received) = try roundTrip(.grant(grant)) else { return XCTFail("not a grant") }
        XCTAssertEqual(GlucoseAlertSettings(encoded: received.glucoseAlertSettings), settings)

        let older = LoanGrant(epoch: 4, expiresAt: Date(), pumpConfiguration: Data([1]), podAddress: 0,
                              therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC", doseHistory: [])
        guard case .grant(let fromOlder) = try roundTrip(.grant(older)) else { return XCTFail("not a grant") }
        XCTAssertNil(fromOlder.glucoseAlertSettings)
    }

    /// The override history rides the grant; nil from an older phone. An older watch ignores it,
    /// as JSON decoding ignores any key its type does not declare.
    func testGrantOverrideHistoryRoundTripsAndIsOptional() throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000)
        let exercise = TemporaryPreset(symbol: "🏃", name: "Exercise",
                                       settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter,
                                                                         targetRange: DoubleRange(minValue: 140, maxValue: 160),
                                                                         insulinNeedsScaleFactor: 0.5),
                                       duration: .finite(.hours(2)))
        var morning = exercise.createOverride(enactTrigger: .local, beginningAt: now.addingTimeInterval(-.hours(20)))
        morning.actualEnd = .early(now.addingTimeInterval(-.hours(19)))
        let preMeal = TemporaryScheduleOverride(context: .preMeal,
                                                settings: TemporaryPresetSettings(unit: .milligramsPerDeciliter,
                                                                                  targetRange: DoubleRange(minValue: 80, maxValue: 80),
                                                                                  insulinNeedsScaleFactor: nil),
                                                startDate: now.addingTimeInterval(-.hours(6)), duration: .finite(.hours(1)),
                                                enactTrigger: .local, syncIdentifier: UUID())
        let current = exercise.createOverride(enactTrigger: .local, beginningAt: now.addingTimeInterval(-.minutes(30)))
        let raw = try XCTUnwrap(LoanGrant.overrideHistoryRaw([morning, preMeal, current]))

        func grant(_ history: Data?) -> LoanGrant {
            LoanGrant(epoch: 4, expiresAt: now, pumpConfiguration: Data([1]), podAddress: 0,
                      therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC", doseHistory: [], overrideHistoryRaw: history)
        }
        guard case .grant(let received) = try roundTrip(.grant(grant(raw))) else { return XCTFail("not a grant") }
        let history = try XCTUnwrap(received.overrideHistory)
        XCTAssertEqual(history.map(\.syncIdentifier), [morning, preMeal, current].map(\.syncIdentifier))
        XCTAssertEqual(history[0].scheduledEndDate, morning.actualEndDate, "an early end folds into the duration")
        XCTAssertEqual(history[2].context, current.context)

        guard case .grant(let fromOlder) = try roundTrip(.grant(grant(nil))) else { return XCTFail("not a grant") }
        XCTAssertNil(fromOlder.overrideHistory, "an older phone: nil, so the watch keeps only the active override")

        // What a watch without the field sees: an undeclared key, which decoding skips.
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: LoanProtocol.encoder.encode(LoanEnvelope(message: .grant(grant(nil))))) as? [String: Any])
        var body = try XCTUnwrap(envelope["body"] as? [String: Any])
        body["aFieldFromANewerPhone"] = raw.base64EncodedString()
        envelope["body"] = body
        let skewed = try JSONSerialization.data(withJSONObject: envelope)
        guard case .grant? = try LoanMessage.decode(fromTransport: [LoanProtocol.userInfoKey: skewed]) else {
            return XCTFail("an unknown grant field must not make the grant unreadable")
        }

        let withField = try LoanProtocol.encoder.encode(LoanEnvelope(message: .grant(grant(raw)))).count
        let without = try LoanProtocol.encoder.encode(LoanEnvelope(message: .grant(grant(nil)))).count
        print("OVERRIDE-HISTORY-SIZE plist=\(raw.count)B grant +\(withField - without)B for 3 overrides")
        XCTAssertLessThan(withField - without, 4_000, "a day of overrides stays small beside the 60 KB urgent limit")
    }

    /// The settings history rides the grant; nil from an older phone. Built the way the phone
    /// builds it, by stock's queries over a settings store, with every value changed 2 h before.
    func testGrantSettingsHistoryRoundTripsAndIsOptional() async throws {
        let now = Date(timeIntervalSince1970: 1_784_338_000)
        let gmt = TimeZone(identifier: "GMT")!
        let mgdl = LoopUnit.milligramsPerDeciliter

        /// Basal in `basalSegments` equal blocks, ISF in 3, carb ratio in 4, target in 3; `bump` changes every value.
        func storedSettings(at date: Date, basalSegments: Int, bump: Double) -> StoredSettings {
            func items<T>(_ count: Int, _ value: (Int) -> T) -> [RepeatingScheduleValue<T>] {
                (0..<count).map { RepeatingScheduleValue(startTime: .hours(24.0 * Double($0) / Double(count)), value: value($0)) }
            }
            return StoredSettings(
                date: date,
                glucoseTargetRangeSchedule: GlucoseRangeSchedule(unit: mgdl, dailyItems: items(3) { DoubleRange(minValue: 100 + 5 * Double($0) + bump, maxValue: 110 + 5 * Double($0) + bump) }, timeZone: gmt),
                basalRateSchedule: BasalRateSchedule(dailyItems: items(basalSegments) { 0.8 + 0.05 * Double($0) + bump / 10 }, timeZone: gmt),
                insulinSensitivitySchedule: InsulinSensitivitySchedule(unit: mgdl, dailyItems: items(3) { 45 + 5 * Double($0) + bump }, timeZone: gmt),
                carbRatioSchedule: CarbRatioSchedule(unit: .gram, dailyItems: items(4) { 10 + Double($0) + bump }, timeZone: gmt))
        }

        /// What the phone's grant assembly sends for a day with one change 2 h before it.
        func phoneHistory(basalSegments: Int) async throws -> LoanSettingsHistory {
            let cache = PersistenceController(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            let store = SettingsStore(store: cache, expireAfter: .days(7))
            for settings in [storedSettings(at: now.addingTimeInterval(-.hours(30)), basalSegments: basalSegments, bump: 0),
                             storedSettings(at: now.addingTimeInterval(-.hours(2)), basalSegments: basalSegments, bump: 2)] {
                await withCheckedContinuation { done in store.storeSettings(settings) { _ in done.resume() } }
            }
            let start = now.addingTimeInterval(-.hours(24))
            return LoanSettingsHistory(
                basal: try await store.getBasalHistory(startDate: start, endDate: now),
                sensitivity: try await store.getInsulinSensitivityHistory(startDate: start, endDate: now),
                carbRatio: try await store.getCarbRatioHistory(startDate: start, endDate: now),
                targetRange: try await store.getTargetRangeHistory(startDate: start, endDate: now))
        }

        func grant(_ history: LoanSettingsHistory?) -> LoanGrant {
            LoanGrant(epoch: 4, expiresAt: now, pumpConfiguration: Data([1]), podAddress: 0,
                      therapySettingsRaw: Data([2]), settingsTimeZoneID: "UTC", doseHistory: [], settingsHistory: history)
        }
        func value(_ timeline: [AbsoluteScheduleValue<Double>], at date: Date) -> Double? {
            timeline.first { $0.startDate <= date && date < $0.endDate }?.value
        }

        let history = try await phoneHistory(basalSegments: 6)
        guard case .grant(let received) = try roundTrip(.grant(grant(history))) else { return XCTFail("not a grant") }
        XCTAssertEqual(received.settingsHistory, history)
        let carried = try XCTUnwrap(received.settingsHistory)
        // `now` is 01:26 GMT: 3 h before is the last block of the old schedules (the new ones would
        // read 1.25 U/h and 57 there), 1 h before is the first block of the new ones.
        XCTAssertEqual(try XCTUnwrap(value(carried.basal, at: now.addingTimeInterval(-.hours(3)))), 1.05, accuracy: 0.001, "the old rate before the change")
        XCTAssertEqual(try XCTUnwrap(value(carried.basal, at: now.addingTimeInterval(-.hours(1)))), 1.0, accuracy: 0.001, "the new one after")
        XCTAssertEqual(try XCTUnwrap(value(carried.sensitivity, at: now.addingTimeInterval(-.hours(3)))), 55, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(value(carried.sensitivity, at: now.addingTimeInterval(-.hours(1)))), 47, accuracy: 0.001)
        XCTAssertEqual(carried.basal.last?.endDate, now, "up to the grant")

        guard case .grant(let fromOlder) = try roundTrip(.grant(grant(nil))) else { return XCTFail("not a grant") }
        XCTAssertNil(fromOlder.settingsHistory, "an older phone: nil, so the watch projects its snapshot back")

        let without = try LoanProtocol.encoder.encode(LoanEnvelope(message: .grant(grant(nil)))).count
        let typical = try LoanProtocol.encoder.encode(LoanEnvelope(message: .grant(grant(history)))).count - without
        let hourly = try LoanProtocol.encoder.encode(LoanEnvelope(message: .grant(grant(try await phoneHistory(basalSegments: 24))))).count - without
        print("SETTINGS-HISTORY-SIZE grant +\(typical)B (basal in 6 blocks), +\(hourly)B (hourly basal); entries \(history.basal.count)/\(history.sensitivity.count)/\(history.carbRatio.count)/\(history.targetRange.count)")
        XCTAssertLessThan(typical, 4_000, "a day of settings stays small beside the 60 KB urgent limit")
    }

    func testAGrantWithoutAConfigurationDecodesToNil() {
        let grant = LoanGrant(epoch: 4, expiresAt: Date(), pumpConfiguration: Data([1, 2, 3]), podAddress: 0,
                              therapySettingsRaw: Data(), settingsTimeZoneID: "UTC", doseHistory: [])
        XCTAssertNil(grant.sharedPumpConfiguration)
    }

    /// Version 3 changed the grant's pump field; a version-2 peer is refused, never guessed at.
    func testAVersion2PeerIsRefused() throws {
        XCTAssertEqual(LoanProtocol.version, 3)
        var dict = try LoanMessage.revoke(Revoke(epoch: 1)).transportDictionary()
        var json = try JSONSerialization.jsonObject(with: dict[LoanProtocol.userInfoKey] as! Data) as! [String: Any]
        json["protocolVersion"] = 2
        dict[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try LoanMessage.decode(fromTransport: dict)) { error in
            guard case LoanProtocolError.undecodable(let seen) = error else { return XCTFail() }
            XCTAssertEqual(seen, 2)
        }
    }

    func testForeignPayloadIsNotOurs() throws {
        XCTAssertNil(try LoanMessage.decode(fromTransport: ["somethingElse": Data([1])]))
    }

    func testVersionSkewThrowsNeverDiscards() throws {
        var dict = try LoanMessage.revoke(Revoke(epoch: 1)).transportDictionary()
        var json = try JSONSerialization.jsonObject(with: dict[LoanProtocol.userInfoKey] as! Data) as! [String: Any]
        json["protocolVersion"] = 99
        dict[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try LoanMessage.decode(fromTransport: dict)) { error in
            guard case LoanProtocolError.undecodable(let seen) = error else { return XCTFail() }
            XCTAssertEqual(seen, 99)
        }
    }

    func testUnknownKindThrows() throws {
        var dict = try LoanMessage.revoke(Revoke(epoch: 1)).transportDictionary()
        var json = try JSONSerialization.jsonObject(with: dict[LoanProtocol.userInfoKey] as! Data) as! [String: Any]
        json["kind"] = "futureMessage"
        dict[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)
        XCTAssertThrowsError(try LoanMessage.decode(fromTransport: dict))
    }

    /// An offer with the `released` key absent (older watch) decodes as nil, meaning final.
    func testLegacyOfferWithoutReleasedKeyDecodesAsNil() throws {
        let offer = HandbackOffer(epoch: 7, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [], tombstones: [], recovered: false, released: true)
        var dict = try LoanMessage.handbackOffer(offer).transportDictionary()
        var json = try JSONSerialization.jsonObject(with: dict[LoanProtocol.userInfoKey] as! Data) as! [String: Any]
        XCTAssertTrue(Self.stripKey("released", from: &json), "fixture must actually contain a released key to strip")
        dict[LoanProtocol.userInfoKey] = try JSONSerialization.data(withJSONObject: json)

        guard case .handbackOffer(let decoded) = try LoanMessage.decode(fromTransport: dict) else {
            return XCTFail("expected a handbackOffer")
        }
        XCTAssertNil(decoded.released, "an absent key decodes as nil, not as false")
        XCTAssertEqual(decoded.epoch, 7, "the rest of the payload still decodes")
    }

    // MARK: - Pulse model

    /// Pulses restart on every command, so a truncated temp loses its partial pulse: 2.15 U/hr
    /// over 302 s is 3 pulses (0.150 U), not 0.180 U.
    func testExpectedInsulinModelsPodPulsesNotRateTimesTime() {
        let start = loanStart
        let temp = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                             record: LoanDoseRecord(kind: .tempBasal, startDate: start,
                                                    endDate: start.addingTimeInterval(302),
                                                    unitsPerHour: 2.15),
                             loggedAt: start)

        let expected = LoanReconciler.expectedInsulin(events: [temp], schedule: nil, pulseUnits: 0.05,
                                                      from: start, to: start.addingTimeInterval(302))

        XCTAssertEqual(expected, 0.150, accuracy: 0.0001,
                       "3 whole pulses — the 4th was still 51 s away when the temp was replaced")
        XCTAssertLessThan(expected, 2.15 * 302 / 3600,
                          "must be strictly less than rate×time: the partial pulse is never delivered")
    }

    /// A bolus is commanded as a pulse count, so it has no partial-pulse tail and must stay exact —
    /// otherwise the fix for basal quantization would introduce a NEW bias on boluses.
    func testExpectedInsulinLeavesBolusesExact() {
        let start = loanStart
        let bolus = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                              record: LoanDoseRecord(kind: .bolus, startDate: start, amount: 1.60),
                              loggedAt: start)

        let expected = LoanReconciler.expectedInsulin(events: [bolus], schedule: nil, pulseUnits: 0.05,
                                                      from: start, to: start.addingTimeInterval(60))
        XCTAssertEqual(expected, 1.60, accuracy: 0.0001)
    }

    /// The bias is per-REPLACEMENT, which is why it grows with loan length: ten identical
    /// five-minute segments lose ten partial pulses, where one fifty-minute segment loses one.
    func testQuantizationLossScalesWithTheNumberOfReplacements() {
        let start = loanStart
        let rate = 1.15   // a pulse every 156.5 s — 300 s gives 1 whole pulse, 0.92 lost
        var chopped: [LoanEvent] = []
        for i in 0..<10 {
            let segStart = start.addingTimeInterval(Double(i) * 300)
            chopped.append(LoanEvent(id: UUID(), seq: i + 1, provenance: .confirmed,
                                     record: LoanDoseRecord(kind: .tempBasal, startDate: segStart,
                                                            endDate: segStart.addingTimeInterval(300),
                                                            unitsPerHour: rate),
                                     loggedAt: segStart))
        }
        let whole = [LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                               record: LoanDoseRecord(kind: .tempBasal, startDate: start,
                                                      endDate: start.addingTimeInterval(3000),
                                                      unitsPerHour: rate),
                               loggedAt: start)]

        let end = start.addingTimeInterval(3000)
        let choppedTotal = LoanReconciler.expectedInsulin(events: chopped, schedule: nil, pulseUnits: 0.05, from: start, to: end)
        let wholeTotal = LoanReconciler.expectedInsulin(events: whole, schedule: nil, pulseUnits: 0.05, from: start, to: end)

        // The loss is per replacement, so it grows with loan length.
        XCTAssertLessThan(choppedTotal, wholeTotal,
                          "replacing the temp every 5 min delivers strictly less than leaving it alone")
        XCTAssertEqual(wholeTotal - choppedTotal, 0.45, accuracy: 0.0001,
                       "10 replacements lose 9 more pulses than 1 continuous segment does")
    }

    /// Recursively remove `key` wherever it appears; returns whether anything was removed.
    /// The offer's nesting inside the envelope is an encoding detail this test should not pin.
    private static func stripKey(_ key: String, from json: inout [String: Any]) -> Bool {
        var removed = false
        if json.removeValue(forKey: key) != nil { removed = true }
        for (k, v) in json {
            if var child = v as? [String: Any] {
                if stripKey(key, from: &child) { json[k] = child; removed = true }
            }
        }
        return removed
    }

    // MARK: - Allocation fixtures

    private let loanStart = Date(timeIntervalSinceReferenceDate: 700_000_000)
    private var loanEnd: Date { loanStart.addingTimeInterval(7200) }  // 2 h loan

    private var flatSchedule: BasalRateSchedule {
        BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)], timeZone: TimeZone(identifier: "GMT")!)!
    }

    private func bolusEvent(seq: Int, units: Double, provenance: EventProvenance, at offset: TimeInterval) -> LoanEvent {
        LoanEvent(id: UUID(), seq: seq, provenance: provenance,
                  record: LoanDoseRecord(kind: .bolus, startDate: loanStart.addingTimeInterval(offset), amount: units),
                  loggedAt: loanStart.addingTimeInterval(offset))
    }

    private func reconcile(events: [LoanEvent]) -> LoanReconciler.Outcome {
        LoanReconciler.reconcile(LoanReconciler.Input(
            events: events,
            schedule: flatSchedule, loanStart: loanStart, loanEnd: loanEnd))
    }

    // MARK: - Allocation properties

    /// A confirmed event can NEVER be reduced — same arithmetic, confirmed tag.
    func testConfirmedEventsAreNeverAnnulled() {
        let confirmed = bolusEvent(seq: 1, units: 1.0, provenance: .confirmed, at: 600)
        let outcome = reconcile(events: [confirmed])
        // The record is entered IN FULL (max-exposure: never truncate downward).
        XCTAssertEqual(outcome.doses.count, 1)
        XCTAssertEqual(outcome.doses[0].programmedUnits, 1.0)
    }

    // MARK: - Expected-insulin math (journal supersedes schedule, schedule fills gaps)

    func testExpectedInsulinJournalOverridesSchedule() {
        // 2 h window, flat 1.0 U/hr schedule, journaled 2.0 U/hr temp for the 1st hour:
        // expected = 2.0 (temp hour) + 1.0 (schedule hour) = 3.0.
        let temp = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                             record: LoanDoseRecord(kind: .tempBasal, startDate: loanStart,
                                                    endDate: loanStart.addingTimeInterval(3600), unitsPerHour: 2.0),
                             loggedAt: loanStart)
        let expected = LoanReconciler.expectedInsulin(events: [temp], schedule: flatSchedule, pulseUnits: 0.05, from: loanStart, to: loanEnd)
        XCTAssertEqual(expected, 3.0, accuracy: 0.01)
    }

    func testExpectedInsulinSuspendCountsAsZero() {
        // Suspend = rate-0 temp for hour 1: expected = 0 + 1.0 = 1.0.
        let suspend = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed,
                                record: LoanDoseRecord(kind: .suspend, startDate: loanStart,
                                                       endDate: loanStart.addingTimeInterval(3600), unitsPerHour: 0),
                                loggedAt: loanStart)
        let expected = LoanReconciler.expectedInsulin(events: [suspend], schedule: flatSchedule, pulseUnits: 0.05, from: loanStart, to: loanEnd)
        XCTAssertEqual(expected, 1.0, accuracy: 0.01)
    }

    // MARK: - Pump-event reroute
    // Overlaps are collapsed by stock `reconciled()` at the store; the reconciler only finalizes and withholds.

    private func temps(count: Int, spacingSeconds: Double = 300, windowSeconds: Double = 1800,
                       rate: Double = 2.0) -> [LoanEvent] {
        (0..<count).map { i in
            let start = loanStart.addingTimeInterval(Double(i) * spacingSeconds)
            return LoanEvent(id: UUID(), seq: i + 1, provenance: .confirmed,
                             record: LoanDoseRecord(kind: .tempBasal, startDate: start,
                                                    endDate: start.addingTimeInterval(windowSeconds), unitsPerHour: rate),
                             loggedAt: start)
        }
    }

    /// Final hand-back: every dose finalized and clamped to loanEnd; overlaps left to the store.
    func testFinalHandbackFinalizesAndClampsToLoanEnd() {
        let events = temps(count: 3)  // 30-min windows, 5 min apart
        let loanEnd = loanStart.addingTimeInterval(1500)  // 25 min: every window overruns it
        let outcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: events, schedule: flatSchedule,
            loanStart: loanStart, loanEnd: loanEnd))

        XCTAssertNil(outcome.openEventID, "nothing is open on a final hand-back")
        XCTAssertEqual(outcome.doses.count, 3)
        for dose in outcome.doses {
            XCTAssertFalse(dose.isMutable, "final-hand-back doses are finalized")
            XCTAssertEqual(dose.endDate, loanEnd, "each 30-min window overruns loanEnd, so all clamp to it (not deferred)")
        }
    }

    /// Interim drain: the open temp is acked but withheld from the write and committed IDs.
    func testInterimDrainWithholdsOpenTempFromWrite() {
        let events = temps(count: 3)
        // Drain 12 min in — all three 30-min windows still extend past it; temp[2] is open.
        let outcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: events, schedule: flatSchedule,
            loanStart: loanStart, loanEnd: loanStart.addingTimeInterval(720),
            isFinalHandback: false))

        XCTAssertEqual(outcome.openEventID, events[2].id, "the latest-starting still-running temp is open")
        // The open temp is NOT written; the two superseded temps are, immutable & uncapped.
        XCTAssertEqual(outcome.doses.count, 2)
        XCTAssertFalse(outcome.doses.contains { $0.isMutable }, "no mutable loan doses")
        let openSyncID = LoanReconciler.syncIdentifier(for: events[2])
        XCTAssertFalse(outcome.doses.contains { $0.syncIdentifier == openSyncID }, "open temp withheld from write")
        XCTAssertTrue(outcome.doses.contains { $0.syncIdentifier == LoanReconciler.syncIdentifier(for: events[0]) })
    }

    /// A single completed temp on a final hand-back keeps its (sub-loanEnd) window intact.
    func testSingleCompletedTempKeepsWindow() {
        let event = temps(count: 1)[0]  // [0, 1800]
        let outcome = LoanReconciler.reconcile(LoanReconciler.Input(
            events: [event], schedule: flatSchedule,
            loanStart: loanStart, loanEnd: loanStart.addingTimeInterval(3600)))  // loanEnd well past the window
        XCTAssertEqual(outcome.doses.count, 1)
        XCTAssertFalse(outcome.doses[0].isMutable)
        XCTAssertEqual(outcome.doses[0].programmedUnits, 1.0, accuracy: 0.01)  // 2.0 × 0.5h, unclamped
    }

    // MARK: - LoanSeedIdentity (double-hex fix)

    /// The seed's raw round-trips the phone's hex syncIdentifier, so re-reports collide.
    func testLoanSeedIdentityRawRoundTripAndFallbacks() {
        let podRaw = Data("tempBasal 2.35 2026-07-28T21:38:02Z".utf8)   // OmniBLE uniqueKey shape
        let phoneSyncId = podRaw.map { String(format: "%02hhx", $0) }.joined()

        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: phoneSyncId), podRaw, "hex decodes to original bytes")
        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: phoneSyncId.uppercased()), podRaw, "case-insensitive")

        // Identity stability: hex(decoded) == the phone's syncId → the watch stores the SAME syncIdentifier.
        let watchSyncId = LoanSeedIdentity.raw(forSyncIdentifier: phoneSyncId).map { String(format: "%02hhx", $0) }.joined()
        XCTAssertEqual(watchSyncId, phoneSyncId)

        // Non-hex identifiers keep the utf8 encoding (old-phone epoch-keyed fallback, UUID-style ids).
        let epochKeyed = "loanv2-grant-47-0"
        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: epochKeyed), Data(epochKeyed.utf8))
        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: "abc"), Data("abc".utf8), "odd length is not hex")
        XCTAssertEqual(LoanSeedIdentity.raw(forSyncIdentifier: ""), Data(), "empty stays empty via fallback")
    }

    // MARK: - The seed carries finished history only; live doses belong to the pod

    func testSeedDoseEntriesSplitsLiveFromFinished() {
        let now = Date()
        let finishedBolus = LoanDoseRecord(kind: .bolus, startDate: now.addingTimeInterval(-1800),
                                           endDate: now.addingTimeInterval(-1754), amount: 2.0)
        let finishedTemp = LoanDoseRecord(kind: .tempBasal, startDate: now.addingTimeInterval(-3600),
                                          endDate: now.addingTimeInterval(-1800), unitsPerHour: 2.0)
        let runningTemp = LoanDoseRecord(kind: .tempBasal, startDate: now.addingTimeInterval(-600),
                                         endDate: now.addingTimeInterval(1200), unitsPerHour: 2.0)
        let grant = LoanGrant(epoch: 9, expiresAt: now.addingTimeInterval(60), pumpConfiguration: Data(),
                              podAddress: 0x1F0F, therapySettingsRaw: Data(), settingsTimeZoneID: "UTC",
                              doseHistory: [finishedBolus, finishedTemp, runningTemp])

        let (seed, live) = grant.seedDoseEntries(finishedBy: now)
        XCTAssertEqual(seed.count, 2, "finished bolus + finished temp are seedable history")
        XCTAssertEqual(live.count, 1, "the running temp is live — pod state owns it, never seeded")
        XCTAssertEqual(live.first?.unitsPerHour, 2.0)
        XCTAssertTrue(live.first!.endDate > now)
        XCTAssertFalse(seed.contains { $0.endDate > now }, "nothing still-delivering may enter the seed")
        // The split is a partition of the unfiltered seed set.
        XCTAssertEqual(seed.count + live.count, grant.seedDoseEntries().count)
    }

    // MARK: - Channel classification

    /// `.takeoverComplete` rides the immediate channel, or "Taking over…" outlives the takeover.
    func testTakeoverCompleteRidesTheImmediateChannel() {
        let status = LoanPodStatus(timestamp: Date(), deliveredUnits: 1, reservoirLevel: nil, isSuspended: false, faultCode: nil)
        XCTAssertTrue(LoanMessage.takeoverComplete(TakeoverComplete(epoch: 1, firstPodStatus: status)).isInteractiveHandshake,
                      "the tile's 'Taking over…' state depends on this arriving promptly")
    }

    /// The other side of the rule, so the fix cannot be over-applied: background bookkeeping stays
    /// on the guaranteed, relaunch-surviving queue that the cursor/ID machinery is built around.
    func testBackgroundBookkeepingStaysOnTheQueuedChannel() {
        XCTAssertFalse(LoanMessage.doseRecordBatch(DoseRecordBatch(epoch: 1, events: [], tombstones: [])).isInteractiveHandshake)
        XCTAssertFalse(LoanMessage.statusQuery(StatusQuery(epoch: 1)).isInteractiveHandshake)
        XCTAssertFalse(LoanMessage.diag(LoanDiag(epoch: 1, text: "x")).isInteractiveHandshake)
    }

    // MARK: - Transport kind peek

    /// The peek names hand-back offers exactly and returns nil for anything else.
    func testPeekKindIdentifiesOffersAndRejectsForeignPayloads() throws {
        let offer = HandbackOffer(epoch: 3, handedBackAt: Date(), finalStatus: nil, odometer: nil,
                                  events: [], tombstones: [], recovered: false, released: false)
        let dict = try LoanMessage.handbackOffer(offer).transportDictionary()
        XCTAssertEqual(LoanMessage.peekKind(transport: dict), "handbackOffer")

        let batch = try LoanMessage.doseRecordBatch(DoseRecordBatch(epoch: 3, events: [], tombstones: [])).transportDictionary()
        XCTAssertEqual(LoanMessage.peekKind(transport: batch), "doseRecordBatch", "streams must NOT peek as offers")

        XCTAssertNil(LoanMessage.peekKind(transport: ["name": "WatchContext"]), "foreign payloads peek as nil")
        XCTAssertNil(LoanMessage.peekKind(transport: [:]))
    }
}

/// Stock's dosing decisions across a loan: the watch's come home once, the doses carry their
/// ids, and the phone stores none of its own while the pod is lent.
@MainActor
final class LoanDosingDecisionTests: XCTestCase {

    // MARK: - Decision ids on the wire

    /// The id rides the dose record into the phone's dose entries; a record from an older peer,
    /// without it, still decodes.
    func testADoseRecordCarriesItsDecisionIdAndAnOlderRecordStillDecodes() throws {
        let decisionId = UUID()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let record = LoanDoseRecord(kind: .bolus, startDate: at, amount: 1.0, syncIdentifier: "0a0b", decisionId: decisionId)
        let decoded = try LoanProtocol.decoder.decode(LoanDoseRecord.self, from: LoanProtocol.encoder.encode(record))
        XCTAssertEqual(decoded.decisionId, decisionId)
        XCTAssertEqual(record.seedDoseEntry(syncIdentifier: "0a0b")?.decisionId, decisionId, "the seed carries it")

        let event = LoanEvent(id: UUID(), seq: 1, provenance: .confirmed, record: record, loggedAt: at)
        let outcome = LoanReconciler.reconcile(LoanReconciler.Input(events: [event], schedule: nil, loanStart: at.addingTimeInterval(-60),
                                                                    loanEnd: at.addingTimeInterval(60), isFinalHandback: true))
        XCTAssertEqual(outcome.doses.first?.decisionId, decisionId, "the reconciler carries it")

        var older = try XCTUnwrap(JSONSerialization.jsonObject(with: LoanProtocol.encoder.encode(record)) as? [String: Any])
        older["decisionId"] = nil
        let fromOlder = try LoanProtocol.decoder.decode(LoanDoseRecord.self, from: JSONSerialization.data(withJSONObject: older))
        XCTAssertNil(fromOlder.decisionId)
        XCTAssertEqual(fromOlder.amount, 1.0)
    }

    // MARK: - The watch's decisions, added once

    private func storedDecisions(_ store: DosingDecisionStore) async throws -> [StoredDosingDecision] {
        try await withCheckedThrowingContinuation { continuation in
            store.executeDosingDecisionQuery(fromQueryAnchor: nil, limit: 1000) { result in
                switch result {
                case .success(_, let decisions): continuation.resume(returning: decisions)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }

    private func add(_ decisions: [StoredDosingDecision], to store: DosingDecisionStore) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            PodLoanPhoneController.addNewDosingDecisions(decisions, to: store) { continuation.resume(with: $0) }
        }
    }

    /// A file delivered twice, or twice at once, adds each decision once.
    func testDecisionsFromTheWatchDeliveredTwiceAreAddedOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DosingDecisionStore(store: PersistenceController(directoryURL: directory), expireAfter: TimeInterval(24 * 3600))
        let decisions = (0..<6).map { i in
            StoredDosingDecision(date: Date().addingTimeInterval(Double(i - 6) * 300), reason: i % 2 == 0 ? "loop" : "updateRemoteRecommendation")
        }

        let first = try await add(decisions, to: store)
        let again = try await add(decisions, to: store)
        XCTAssertEqual(first, 6)
        XCTAssertEqual(again, 0, "the second delivery adds nothing")

        async let a = add(decisions + [StoredDosingDecision(reason: "loop")], to: store)
        async let b = add(decisions, to: store)
        _ = try await (a, b)

        let stored = try await storedDecisions(store)
        XCTAssertEqual(stored.count, 7)
        XCTAssertEqual(Set(stored.map(\.id)).count, 7, "no id twice")
        XCTAssertEqual(Array(stored.prefix(6)).map(\.id), decisions.map(\.id), "in the watch's order")
    }

    // MARK: - The phone's own decisions while the pod is lent

    private var dosingDecisionStore: MockDosingDecisionStore!
    private var glucoseStore: MockGlucoseStore!
    private var loopDataManager: LoopDataManager!
    private var deliveryDelegate: MockDeliveryDelegate!
    private var lent = false

    override func setUp() async throws {
        let now = Date()
        glucoseStore = MockGlucoseStore()
        glucoseStore.storedGlucose = [StoredGlucoseSample(startDate: now.addingTimeInterval(-60), quantity: .glucose(value: 150))]
        let doseStore = MockDoseStore()
        doseStore.lastAddedPumpData = now

        let settings = StoredSettings(
            dosingEnabled: true,
            glucoseTargetRangeSchedule: GlucoseRangeSchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: DoubleRange(minValue: 100, maxValue: 110))]),
            maximumBasalRatePerHour: 6,
            maximumBolus: 5,
            suspendThreshold: GlucoseThreshold(unit: .milligramsPerDeciliter, value: 75),
            basalRateSchedule: BasalRateSchedule(dailyItems: [RepeatingScheduleValue(startTime: 0, value: 1.0)]),
            insulinSensitivitySchedule: InsulinSensitivitySchedule(unit: .milligramsPerDeciliter, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 50)]),
            carbRatioSchedule: CarbRatioSchedule(unit: .gram, dailyItems: [RepeatingScheduleValue(startTime: 0, value: 10)]),
            automaticDosingStrategy: .tempBasalOnly
        )
        let settingsProvider = MockSettingsProvider(settings: settings)
        dosingDecisionStore = MockDosingDecisionStore()
        loopDataManager = LoopDataManager(
            lastLoopCompleted: now,
            temporaryPresetsManager: TemporaryPresetsManager(settingsProvider: settingsProvider, presetHistory: TemporaryScheduleOverrideHistory()),
            settingsProvider: settingsProvider,
            doseStore: doseStore,
            glucoseStore: glucoseStore,
            carbStore: MockCarbStore(),
            crashRecoveryManager: CrashRecoveryManager(alertIssuer: LoopDataManagerTests.MockAlertIssuer()),
            dosingDecisionStore: dosingDecisionStore,
            trustedTimeOffset: { 0 },
            analyticsServicesManager: nil,
            carbAbsorptionModel: .piecewiseLinear
        )
        deliveryDelegate = MockDeliveryDelegate()
        deliveryDelegate.basalDeliveryState = .active(now.addingTimeInterval(-.hours(2)))
        loopDataManager.deliveryDelegate = deliveryDelegate
        lent = false
        loopDataManager.isPumpConnectionReleased = { [unowned self] in self.lent }
    }

    override func tearDown() async throws {
        loopDataManager = nil
    }

    /// While the pod is lent the phone's loop still runs, but stores neither its "loop" decision
    /// nor an "updateRemoteRecommendation"; after reclaim it stores both again.
    func testWhileThePodIsLentThePhoneStoresNoLoopDecisionsAndAfterReclaimItDoes() async {
        lent = true
        await loopDataManager.loop()
        await loopDataManager.updateRemoteRecommendation(force: true)
        XCTAssertEqual(dosingDecisionStore.dosingDecisions.map(\.reason), [], "none while lent")
        XCTAssertNil(deliveryDelegate.lastEnact.tempBasal, "and nothing enacted, as before")

        lent = false
        await loopDataManager.loop()
        XCTAssertEqual(dosingDecisionStore.dosingDecisions.map(\.reason), ["loop", "updateRemoteRecommendation"], "stored again after reclaim")
    }

    /// The error arm too: a cycle that fails while the pod is lent stores no decision.
    func testWhileThePodIsLentAFailedCycleStoresNoDecision() async {
        lent = true
        glucoseStore.storedGlucose = []
        await loopDataManager.loop()
        XCTAssertTrue(dosingDecisionStore.dosingDecisions.isEmpty)

        lent = false
        await loopDataManager.loop()
        XCTAssertEqual(dosingDecisionStore.dosingDecisions.first?.reason, "loop")
        XCTAssertFalse(dosingDecisionStore.dosingDecisions.first?.errors.isEmpty ?? true, "the error arm stores, with the error")
    }
}

/// The watch's stock records of a loan, added to the phone's own stores once each, as the watch
/// recorded them.
@MainActor
final class LoanHistoryIntakeTests: XCTestCase {

    private final class AlertUploadSpy: AlertStoreDelegate {
        var updates = 0
        func alertStoreHasUpdatedAlertData(_ alertStore: AlertStore) { updates += 1 }
    }

    private func watchAlert(_ id: String, issued: Date, acknowledged: Date? = nil, retracted: Date? = nil,
                            syncIdentifier: UUID = UUID()) -> SyncAlertObject {
        let content = Alert.Content(title: "Low Reservoir", body: "10 U insulin or less remaining in Pod. Change Pod soon.",
                                    acknowledgeActionButtonLabel: "OK")
        return SyncAlertObject(identifier: Alert.Identifier(managerIdentifier: "Omnipod", alertIdentifier: id),
                               trigger: .immediate, interruptionLevel: .timeSensitive, foregroundContent: content,
                               backgroundContent: content, sound: nil, metadata: nil, issuedDate: issued,
                               acknowledgedDate: acknowledged, retractedDate: retracted, syncIdentifier: syncIdentifier)
    }

    /// Each alert is added once, under the watch's sync identifier and with the watch's dates,
    /// however often the file comes; a later copy fills in the retraction. Adding one tells the
    /// store's delegate, which is what starts stock's alert upload, and the upload query sees it.
    func testAlertsFromTheWatchAreAddedOnceWithTheirOwnIdentityAndDates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AlertStore(storageDirectoryURL: directory)
        let spy = AlertUploadSpy()
        store.delegate = spy
        let issued = Date(timeIntervalSinceNow: -3600)
        let low = watchAlert("lowReservoir", issued: issued, acknowledged: issued.addingTimeInterval(30))
        let expiring = watchAlert("podExpiring", issued: issued.addingTimeInterval(600))

        let first = try await store.recordAlerts(fromAnotherDevice: [low, expiring])
        let again = try await store.recordAlerts(fromAnotherDevice: [low, expiring])
        XCTAssertEqual(first, 2)
        XCTAssertEqual(again, 0, "the second delivery adds nothing")
        XCTAssertEqual(spy.updates, 1, "the upload is started once, for the change")

        async let a = store.recordAlerts(fromAnotherDevice: [low, expiring])
        async let b = store.recordAlerts(fromAnotherDevice: [low, expiring])
        _ = try await (a, b)

        let retracted = watchAlert("podExpiring", issued: expiring.issuedDate, retracted: issued.addingTimeInterval(900),
                                   syncIdentifier: expiring.syncIdentifier)
        let updated = try await store.recordAlerts(fromAnotherDevice: [retracted])
        XCTAssertEqual(updated, 1)

        let records = try await store.fetch()
        XCTAssertEqual(records.count, 2, "no alert twice")
        XCTAssertEqual(records.map(\.syncIdentifier), [low.syncIdentifier, expiring.syncIdentifier])
        XCTAssertEqual(records.map(\.issuedDate), [low.issuedDate, expiring.issuedDate], "the watch's dates")
        XCTAssertEqual(records.first?.acknowledgedDate, low.acknowledgedDate)
        XCTAssertEqual(records.last?.retractedDate, retracted.retractedDate)
        XCTAssertEqual(records.first?.title, "Low Reservoir")

        let (_, uploadable) = try await store.executeAlertQuery(fromQueryAnchor: nil, limit: 100)
        XCTAssertEqual(Set(uploadable.map(\.syncIdentifier)), [low.syncIdentifier, expiring.syncIdentifier], "the upload query finds them")
    }

    /// Each line is added once with the watch's own time, however often the file comes, beside
    /// the phone's own lines for the same span; a line of a type this phone does not know is skipped.
    func testDeviceLogLinesFromTheWatchAreAddedOnceWithTheirOwnTimes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let deviceLog = PersistentDeviceLog(storageFile: directory.appendingPathComponent("Storage.sqlite"))
        await withCheckedContinuation { continuation in
            deviceLog.log(managerIdentifier: "G7CGMManager", deviceIdentifier: "DXCMqL", type: .connection,
                          message: "Sensor connected") { _ in continuation.resume() }
        }
        let at = Date(timeIntervalSinceNow: -1800)
        func line(_ type: DeviceLogEntryType, _ message: String, _ offset: TimeInterval) -> LoanDeviceLogEntry {
            LoanDeviceLogEntry(StoredDeviceLogEntry(type: type, managerIdentifier: "Omni", deviceIdentifier: "177E6B7D",
                                                    message: message, timestamp: at.addingTimeInterval(offset)))
        }
        let send = line(.send, "177e6b7d34030e01070200", 0)
        let receive = line(.receive, "177e6b7d380a1d1801b81800002bbfff001d", 0.8)
        let sameInstant = line(.connection, "Pod disconnected 8752D1D3-2009-8769-2091-F5B0CE32418E nil", 0.8)
        var raw = try XCTUnwrap(PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(send), format: nil) as? [String: Any])
        raw["type"] = "someFutureType"
        raw["message"] = "from a newer watch"
        let newer = try PropertyListDecoder().decode(LoanDeviceLogEntry.self,
                                                     from: PropertyListSerialization.data(fromPropertyList: raw, format: .binary, options: 0))
        let lines = [send, receive, sameInstant, newer]

        func add(_ lines: [LoanDeviceLogEntry]) async throws -> Int {
            try await withCheckedThrowingContinuation { continuation in
                PodLoanPhoneController.addNewDeviceLogEntries(lines, to: deviceLog) { continuation.resume(with: $0) }
            }
        }
        let first = try await add(lines)
        let again = try await add(lines)
        XCTAssertEqual(first, 3, "the unknown type skipped")
        XCTAssertEqual(again, 0, "the second delivery adds nothing")
        async let a = add(lines)
        async let b = add(lines)
        _ = try await (a, b)

        let stored = try await deviceLog.fetch(startDate: .distantPast, endDate: .distantFuture)
        XCTAssertEqual(stored.count, 4, "the phone's own line and the watch's three, once each")
        let fromWatch = stored.filter { $0.managerIdentifier == "Omni" }.map(LoanDeviceLogEntry.init)
        XCTAssertEqual(Set(fromWatch), [send, receive, sameInstant], "with the watch's own times")
    }
}
