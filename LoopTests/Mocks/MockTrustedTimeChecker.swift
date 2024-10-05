//
//  MockTrustedTimeChecker.swift
//  LoopTests
//
//  Created by Pete Schwamb on 11/1/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
@testable import Loop

class MockTrustedTimeChecker: TrustedTimeChecker {
    var detectedSystemTimeOffset: TimeInterval = 0
}
