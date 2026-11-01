//
//  LoopControlMock.swift
//  LoopTests
//
//  Created by Pete Schwamb on 11/30/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import XCTest
import Foundation
import LoopKit
@testable import Loop


class LoopControlMock: LoopControl {
    var automatedTreatmentState: AutomatedTreatmentState?
    
    var lastLoopCompleted: Date?

    var lastCancelActiveTempBasalReason: CancelActiveTempBasalReason?

    var cancelExpectation: XCTestExpectation?

    func cancelActiveTempBasal(for reason: CancelActiveTempBasalReason) async {
        lastCancelActiveTempBasalReason = reason
        cancelExpectation?.fulfill()
    }    

    func loop() async {
    }

}
