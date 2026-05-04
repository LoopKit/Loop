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
