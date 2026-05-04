//
//  SiteAtlas_Models.swift
//  Loop
//
//  SiteAtlas — Data models for site rotation tracking.
//
//  Idea by Taylor Patterson. Coded by Claude Code.
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import SwiftUI

// MARK: - Site Type

/// The type of device site being tracked.
enum SiteAtlas_SiteType: String, Codable, CaseIterable {
    case pump
    case sensor

    var displayName: String {
        switch self {
        case .pump: return "Pump Site"
        case .sensor: return "CGM Sensor"
        }
    }

    var iconName: String {
        switch self {
        case .pump: return "cross.circle.fill"
        case .sensor: return "sensor.fill"
        }
    }

    var color: Color {
        switch self {
        case .pump: return SiteAtlas_Theme.primaryColor
        case .sensor: return SiteAtlas_Theme.sensorColor
        }
    }
}

// MARK: - Body Side

/// Which side of the body map the site is on.
enum SiteAtlas_BodySide: String, Codable, CaseIterable {
    case front
    case back

    var displayName: String {
        switch self {
        case .front: return "Front"
        case .back: return "Back"
        }
    }
}

// MARK: - Site Entry

/// A single recorded site placement.
struct SiteAtlas_SiteEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var type: SiteAtlas_SiteType
    var date: Date
    let bodySide: SiteAtlas_BodySide
    var normalizedX: Double
    var normalizedY: Double
    var notes: String?
    var isHidden: Bool

    init(
        id: UUID = UUID(),
        type: SiteAtlas_SiteType,
        date: Date = Date(),
        bodySide: SiteAtlas_BodySide,
        normalizedX: Double,
        normalizedY: Double,
        notes: String? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.type = type
        self.date = date
        self.bodySide = bodySide
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.notes = notes
        self.isHidden = isHidden
    }

    // Backward-compatible decoder — existing JSON won't have isHidden
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(SiteAtlas_SiteType.self, forKey: .type)
        date = try container.decode(Date.self, forKey: .date)
        bodySide = try container.decode(SiteAtlas_BodySide.self, forKey: .bodySide)
        normalizedX = try container.decode(Double.self, forKey: .normalizedX)
        normalizedY = try container.decode(Double.self, forKey: .normalizedY)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    /// Days since this site was placed.
    var daysSincePlaced: Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }
}

// MARK: - Recommended Zone

/// A predefined recommended placement zone on the body map.
struct SiteAtlas_Zone: Identifiable, Equatable {
    let id: String          // Unique key, e.g. "front_abdomen_left"
    let displayName: String
    let bodySide: SiteAtlas_BodySide
    /// Center of the zone in normalized coords (0-1).
    let centerX: Double
    let centerY: Double
    /// Ellipse radii in normalized coords.
    let radiusX: Double
    let radiusY: Double
}

/// All 14 recommended placement zones.
enum SiteAtlas_Zones {

    static let all: [SiteAtlas_Zone] = [
        // ── Front body ──
        SiteAtlas_Zone(id: "front_abdomen_left",  displayName: "Front Abdomen (Left)",
                       bodySide: .front, centerX: 0.58, centerY: 0.44, radiusX: 0.10, radiusY: 0.06),
        SiteAtlas_Zone(id: "front_abdomen_right", displayName: "Front Abdomen (Right)",
                       bodySide: .front, centerX: 0.42, centerY: 0.44, radiusX: 0.10, radiusY: 0.06),
        SiteAtlas_Zone(id: "side_abdomen_left",   displayName: "Side Abdomen (Left)",
                       bodySide: .front, centerX: 0.68, centerY: 0.42, radiusX: 0.06, radiusY: 0.06),
        SiteAtlas_Zone(id: "side_abdomen_right",  displayName: "Side Abdomen (Right)",
                       bodySide: .front, centerX: 0.32, centerY: 0.42, radiusX: 0.06, radiusY: 0.06),
        SiteAtlas_Zone(id: "front_thigh_left",    displayName: "Front Thigh (Left)",
                       bodySide: .front, centerX: 0.58, centerY: 0.62, radiusX: 0.07, radiusY: 0.08),
        SiteAtlas_Zone(id: "front_thigh_right",   displayName: "Front Thigh (Right)",
                       bodySide: .front, centerX: 0.42, centerY: 0.62, radiusX: 0.07, radiusY: 0.08),
        SiteAtlas_Zone(id: "side_thigh_left",     displayName: "Side Thigh (Left)",
                       bodySide: .front, centerX: 0.67, centerY: 0.64, radiusX: 0.05, radiusY: 0.07),
        SiteAtlas_Zone(id: "side_thigh_right",    displayName: "Side Thigh (Right)",
                       bodySide: .front, centerX: 0.33, centerY: 0.64, radiusX: 0.05, radiusY: 0.07),

        // ── Back body ──
        SiteAtlas_Zone(id: "back_arm_left",       displayName: "Back of Arm (Left)",
                       bodySide: .back, centerX: 0.22, centerY: 0.30, radiusX: 0.05, radiusY: 0.07),
        SiteAtlas_Zone(id: "back_arm_right",      displayName: "Back of Arm (Right)",
                       bodySide: .back, centerX: 0.78, centerY: 0.30, radiusX: 0.05, radiusY: 0.07),
        SiteAtlas_Zone(id: "buttocks_left",       displayName: "Buttocks (Left)",
                       bodySide: .back, centerX: 0.42, centerY: 0.52, radiusX: 0.08, radiusY: 0.06),
        SiteAtlas_Zone(id: "buttocks_right",      displayName: "Buttocks (Right)",
                       bodySide: .back, centerX: 0.58, centerY: 0.52, radiusX: 0.08, radiusY: 0.06),
    ]

    /// Zones for a given body side.
    static func zones(for side: SiteAtlas_BodySide) -> [SiteAtlas_Zone] {
        all.filter { $0.bodySide == side }
    }

    /// UserDefaults key for disabled zone IDs.
    private static let disabledKey = "com.loopkit.Loop.siteAtlasDisabledZones"

    /// Currently disabled zone IDs.
    static var disabledZoneIDs: Set<String> {
        get {
            Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: disabledKey)
        }
    }

    /// Whether a zone is enabled (shown on map).
    static func isEnabled(_ zone: SiteAtlas_Zone) -> Bool {
        !disabledZoneIDs.contains(zone.id)
    }

    /// Toggle a zone on or off.
    static func toggleZone(_ zone: SiteAtlas_Zone) {
        var disabled = disabledZoneIDs
        if disabled.contains(zone.id) {
            disabled.remove(zone.id)
        } else {
            disabled.insert(zone.id)
        }
        disabledZoneIDs = disabled
    }
}

// MARK: - Site Data Container

/// Top-level container for JSON persistence.
struct SiteAtlas_SiteData: Codable {
    var entries: [SiteAtlas_SiteEntry]

    init(entries: [SiteAtlas_SiteEntry] = []) {
        self.entries = entries
    }
}

// MARK: - Theme

/// Shared color and style constants for SiteAtlas.
enum SiteAtlas_Theme {
    static let primaryColor = Color(red: 230/255, green: 126/255, blue: 34/255)
    static let sensorColor = Color(red: 41/255, green: 128/255, blue: 185/255)
    static let retentionDays: Int = 365

    /// Age-based pin color: red (fresh) → orange → yellow → green (oldest/safe to reuse).
    /// Transition over 14 days — beyond that stays green.
    static func ageColor(daysSincePlaced days: Int) -> Color {
        let t = min(Double(days) / 14.0, 1.0) // 0 = just placed, 1 = 14+ days
        if t < 0.33 {
            // Red → Orange
            return Color(red: 1.0, green: 0.3 + t * 0.9, blue: 0.2)
        } else if t < 0.66 {
            // Orange → Yellow
            let sub = (t - 0.33) / 0.33
            return Color(red: 1.0, green: 0.6 + sub * 0.4, blue: 0.1)
        } else {
            // Yellow → Green
            let sub = (t - 0.66) / 0.34
            return Color(red: 1.0 - sub * 0.6, green: 0.8 + sub * 0.1, blue: 0.2)
        }
    }
}
