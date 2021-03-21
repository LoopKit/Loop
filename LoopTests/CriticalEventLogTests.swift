//
//  CriticalEventLogTests.swift
//  LoopTests
//
//  Created by Darin Krauss on 8/26/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit

class MockOutputStream: OutputStream {
    var status: Status = .open
    var error: Error? = nil
    var data: Data = Data()

    override var streamStatus: Status { status }
    override var streamError: Error? { error }

    override func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        data.append(UnsafeBufferPointer(start: buffer, count: len))
        return len
    }

    var string: String { String(data: data, encoding: .utf8)! }
}
