//
//  AutomatedTreatmentState.swift
//  Loop
//
//  Created by Pete Schwamb on 10/9/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI

extension AutomatedTreatmentState {
    var shortDescription: String {
        switch self {
        case .neutralNoOverride:
            return NSLocalizedString("Scheduled", comment: "Title for neutral automated treatment state")
        case .neutralOverride:
            return NSLocalizedString("Preset Delivery", comment: "Title for neutral automated treatment state with preset adjusting basal")
        case .increasedInsulin:
            return NSLocalizedString("Increased", comment: "Title for increased insulin automated treatment state")
        case .decreasedInsulin, .minimumDelivery:
            return NSLocalizedString("Decreased", comment: "Title for increased insulin automated treatment state")
        }
    }

    var iconImage: Image {
        switch self {

        case .neutralNoOverride, .neutralOverride:
            Image(systemName: "arrow.right.square.fill")
        case .increasedInsulin:
            Image(systemName: "arrow.up.square.fill")
        case .decreasedInsulin, .minimumDelivery:
            Image(systemName: "arrow.down.square.fill")
        }
    }
}
