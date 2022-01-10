//
//  LoopWarning.swift
//  Loop
//
//  Created by Darin Krauss on 10/22/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

enum FetchDataWarningDetail {
    case glucoseSamples(error: Error)
    case glucoseMomentumEffect(error: Error)
    case insulinEffect(error: Error)
    case insulinEffectIncludingPendingInsulin(error: Error)
    case insulinCounteractionEffect(error: Error)
    case carbEffect(error: Error)
    case carbsOnBoard(error: Error)
    case insulinOnBoard(error: Error)
    case retrospectiveGlucoseEffect(error: Error)
}

extension FetchDataWarningDetail {
    var issueId: String {
        switch self {
        case .glucoseSamples:
            return "glucoseSamples"
        case .glucoseMomentumEffect:
            return "glucoseMomentumEffect"
        case .insulinEffect:
            return "insulinEffect"
        case .insulinEffectIncludingPendingInsulin:
            return "insulinEffectIncludingPendingInsulin"
        case .insulinCounteractionEffect:
            return "insulinCounteractionEffect"
        case .carbEffect:
            return "carbEffect"
        case .carbsOnBoard:
            return "carbsOnBoard"
        case .insulinOnBoard:
            return "insulinOnBoard"
        case .retrospectiveGlucoseEffect:
            return "retrospectiveGlucoseEffect"
        }
    }

    var issueDetails: [String: String] {
        var details = ["detail": issueId]
        switch self {
        case .glucoseSamples(let error),
             .glucoseMomentumEffect(let error),
             .insulinEffect(let error),
             .insulinEffectIncludingPendingInsulin(let error),
             .insulinCounteractionEffect(let error),
             .carbEffect(let error),
             .carbsOnBoard(let error),
             .insulinOnBoard(let error),
             .retrospectiveGlucoseEffect(let error):
            details["error"] = StoredDosingDecisionIssue.description(for: error)
        }
        return details
    }
}

enum LoopWarning {
    case fetchDataWarning(FetchDataWarningDetail)
    case bolusInProgress
}

extension LoopWarning {
    var issue: StoredDosingDecision.Issue {
        return StoredDosingDecision.Issue(id: issueId, details: issueDetails)
    }

    var issueId: String {
        switch self {
        case .fetchDataWarning:
            return "fetchDataWarning"
        case .bolusInProgress:
            return "bolusInProgress"
        }
    }

    var issueDetails: [String: String] {
        var details: [String: String] = [:]
        switch self {
        case .fetchDataWarning(let detail):
            details = detail.issueDetails
        default:
            break
        }
        return details
    }
}

extension Locked where T == [LoopWarning] {
    func append(_ loopWarning: LoopWarning) { mutate { $0.append(loopWarning) } }
}
