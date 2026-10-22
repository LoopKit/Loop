//
//  AlarmSoundCatalogTests.swift
//  LoopTests
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import XCTest
@testable import Loop

final class AlarmSoundCatalogTests: XCTestCase {

    /// The catalog is only a list of names; a typo or a file left out of the
    /// target makes the alarm fall silent at runtime. Tests are hosted in
    /// Loop.app, so the app bundle is what ships.
    func testEveryCatalogFileIsBundled() {
        for filename in AlarmSoundCatalog.allFilenames {
            let resource = (filename as NSString).deletingPathExtension
            let ext = (filename as NSString).pathExtension
            XCTAssertNotNil(
                Bundle.main.url(forResource: resource, withExtension: ext),
                "\(filename) is in the catalog but not bundled"
            )
        }
    }

    func testFilenamesAreUnique() {
        let all = AlarmSoundCatalog.allFilenames
        XCTAssertEqual(Set(all).count, all.count)
    }

    func testEveryAlarmOffersAcousticElectronicAndVoice() {
        for kind in GlucoseAlarmKind.allCases {
            let ids = AlarmSoundCatalog.themedEntries(for: kind).map { $0.id }
            XCTAssertEqual(ids.count, 3, "\(kind) should offer three themed sets")
            XCTAssertTrue(ids.contains { $0.hasPrefix("acoustic.") })
            XCTAssertTrue(ids.contains { $0.hasPrefix("electronic.") })
            XCTAssertTrue(ids.contains { $0.hasPrefix("voice.") })
        }
    }

    /// A themed set is written for one alarm, so it must not surface on another.
    func testThemedSetsAreScopedToOneAlarm() {
        for kind in GlucoseAlarmKind.allCases {
            for entry in AlarmSoundCatalog.themedEntries(for: kind) {
                XCTAssertEqual(entry.kinds, [kind])
            }
        }
    }

    func testGenericTonesAreOfferedEverywhere() {
        for entry in AlarmSoundCatalog.genericTones {
            XCTAssertTrue(entry.isGeneric)
            XCTAssertEqual(entry.variants.count, 1)
            XCTAssertEqual(entry.selector, .none)
        }
        // The legacy tones stay selectable so an upgrade never loses a pick.
        let filenames = AlarmSoundCatalog.genericTones.map { $0.id }
        for legacy in ["urgent_low.caf", "critical.caf", "alarm.caf", "simple.caf", "chime.caf", "mood_synth.caf"] {
            XCTAssertTrue(filenames.contains(legacy), "\(legacy) should remain selectable")
        }
    }

    func testDefaultsAreAcousticMedium() {
        for kind in GlucoseAlarmKind.allCases {
            XCTAssertTrue(
                AlarmSoundCatalog.defaultFilename(for: kind).hasPrefix("acoustic_"),
                "\(kind) should default to the Acoustic set"
            )
            XCTAssertTrue(AlarmSoundCatalog.defaultFilename(for: kind).hasSuffix("_medium.caf"))
        }
        XCTAssertEqual(GlucoseAlertManager.defaultUrgentLowSound, "acoustic_ulg_medium.caf")
        XCTAssertEqual(GlucoseAlertManager.defaultLowSound, "acoustic_lg_medium.caf")
        XCTAssertEqual(GlucoseAlertManager.defaultPredictedLowSound, "acoustic_lgs_medium.caf")
        XCTAssertEqual(GlucoseAlertManager.defaultHighSound, "acoustic_hg_medium.caf")
    }

    /// Only the filename is persisted, so every filename has to lead back to
    /// the row and variant that produced it.
    func testEveryFilenameResolvesBackToItsEntry() {
        for entry in AlarmSoundCatalog.entries {
            for variant in entry.variants {
                XCTAssertEqual(AlarmSoundCatalog.entry(forFilename: variant.filename)?.id, entry.id)
                XCTAssertEqual(entry.variant(forFilename: variant.filename), variant)
            }
        }
    }

    func testDisplayNameNamesTheVariantOnlyForThemedSets() {
        XCTAssertEqual(AlarmSoundCatalog.displayName(for: "acoustic_ulg_medium.caf"), "Acoustic · Medium")
        XCTAssertEqual(AlarmSoundCatalog.displayName(for: "voice_hg_amy.caf"), "Voice · Amy")
        XCTAssertEqual(AlarmSoundCatalog.displayName(for: "chime.caf"), "Chime")
        // An unknown file still shows something rather than an empty row.
        XCTAssertEqual(AlarmSoundCatalog.displayName(for: "gone.caf"), "gone.caf")
    }

    func testThemedEntryDefaultsToTheMediumVariant() {
        for kind in GlucoseAlarmKind.allCases {
            for entry in AlarmSoundCatalog.themedEntries(for: kind) where entry.selector == .urgency {
                XCTAssertEqual(entry.defaultVariant.id, AlarmUrgencyLevel.medium.rawValue)
            }
        }
    }
}
