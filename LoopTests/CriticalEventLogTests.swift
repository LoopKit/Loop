//
//  CriticalEventLogTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 8/26/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class MockOutputStream: DataOutputStream {
    var error: Error? = nil
    var data: Data = Data()
    var finished = false

    var streamError: Error? { return error }

    func write(_ data: Data) throws {
        if let error = self.error {
            throw error
        }
        self.data.append(data)
    }

    func finish(sync: Bool) throws {
        if let error = self.error {
            throw error
        }
        finished = true
    }

    var string: String { String(data: data, encoding: .utf8)! }
}
