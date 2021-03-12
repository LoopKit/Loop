//
//  LoopChartsTableViewController.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopUI
import LoopKitUI
import HealthKit
import os.log


enum RefreshContext: Equatable {
    /// Catch-all for lastLoopCompleted, recommendedTempBasal, lastTempBasal, preferences
    case status

    case glucose
    case insulin
    case carbs
    case targets

    case size(CGSize)
}

extension RefreshContext: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }

    private var rawValue: Int {
        switch self {
        case .status:
            return 1
        case .glucose:
            return 2
        case .insulin:
            return 3
        case .carbs:
            return 4
        case .targets:
            return 5
        case .size:
            // We don't use CGSize in our determination of hash nor equality
            return 6
        }
    }

    static func ==(lhs: RefreshContext, rhs: RefreshContext) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }
}

extension Set where Element == RefreshContext {
    /// Returns the size value in the set if one exists
    var newSize: CGSize? {
        guard let index = firstIndex(of: .size(.zero)),
            case .size(let size) = self[index] else
        {
            return nil
        }

        return size
    }

    /// Removes and returns the size value in the set if one exists
    ///
    /// - Returns: The size, if contained
    mutating func removeNewSize() -> CGSize? {
        guard case .size(let newSize)? = remove(.size(.zero)) else {
            return nil
        }

        return newSize
    }
}

/// Abstract class providing boilerplate setup for chart-based table view controllers
/// The logic is split between Loop and LoopKit because the DeviceDataManager is a Loop-specific concept
open class LoopChartsTableViewController: ChartsTableViewController {
    weak var deviceManager: DeviceDataManager! {
        didSet {
            self.displayGlucoseUnitObservable = deviceManager.displayGlucoseUnitObservable
        }
    }
}

