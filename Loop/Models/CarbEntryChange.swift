//
//  CarbEntryChange.swift
//  Loop
//
//  Copyright © 2026 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopAlgorithm
import LoopKit

/// A carb entry about to be saved: a new entry, or new content for a stored one.
enum CarbEntryChange: Equatable {
    case add(NewCarbEntry)
    case edit(StoredCarbEntry, CarbEntryUpdate)

    var originalEntry: StoredCarbEntry? {
        if case .edit(let original, _) = self {
            return original
        }
        return nil
    }

    var quantity: LoopQuantity {
        switch self {
        case .add(let entry): entry.quantity
        case .edit(_, let update): update.quantity
        }
    }

    var startDate: Date {
        switch self {
        case .add(let entry): entry.startDate
        case .edit(_, let update): update.startDate
        }
    }

    var foodType: String? {
        switch self {
        case .add(let entry): entry.foodType
        case .edit(_, let update): update.foodType
        }
    }

    var absorptionTime: TimeInterval? {
        switch self {
        case .add(let entry): entry.absorptionTime
        case .edit(_, let update): update.absorptionTime
        }
    }

    var asStoredCarbEntry: StoredCarbEntry {
        switch self {
        case .add(let entry): entry.asStoredCarbEntry
        case .edit(_, let update): update.asStoredCarbEntry
        }
    }
}
