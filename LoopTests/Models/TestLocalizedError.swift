//
//  TestLocalizedError.swift
//  LoopTests
//
//  Created by Darin Krauss on 10/21/21.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

struct TestLocalizedError: LocalizedError {
    public let errorDescription: String?
    public let failureReason: String?
    public let helpAnchor: String?
    public let recoverySuggestion: String?

    init(errorDescription: String? = nil, failureReason: String? = nil, helpAnchor: String? = nil, recoverySuggestion: String? = nil) {
        self.errorDescription = errorDescription
        self.failureReason = failureReason
        self.helpAnchor = helpAnchor
        self.recoverySuggestion = recoverySuggestion
    }
}
