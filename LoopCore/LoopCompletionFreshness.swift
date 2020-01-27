//
//  LoopCompletionFreshness.swift
//  Loop
//
//  Created by Pete Schwamb on 1/17/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation

public enum LoopCompletionFreshness {
    case fresh
    case aging
    case stale
    case unknown
    
    public var maxAge: TimeInterval? {
        switch self {
        case .fresh:
            return TimeInterval(minutes: 6)
        case .aging:
            return TimeInterval(minutes: 16)
        case .stale:
            return TimeInterval(hours: 12)
        case .unknown:
            return nil
        }
    }
    
    public init(age: TimeInterval?) {
        guard let age = age else {
            self = .unknown
            return
        }
        
        switch age {
        case let t where t <= LoopCompletionFreshness.fresh.maxAge!:
            self = .fresh
        case let t where t <= LoopCompletionFreshness.aging.maxAge!:
            self = .aging
        case let t where t <= LoopCompletionFreshness.stale.maxAge!:
            self = .stale
        default:
            self = .unknown
        }
    }
    
    public init(lastCompletion: Date?, at date: Date = Date()) {
        guard let lastCompletion = lastCompletion else {
            self = .unknown
            return
        }
        
        self = LoopCompletionFreshness(age: date.timeIntervalSince(lastCompletion))
    }

}
