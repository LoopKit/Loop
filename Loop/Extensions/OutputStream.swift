//
//  OutputStream.swift
//  Loop
//
//  Created by Darin Krauss on 8/28/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation

extension OutputStream {
    func write(_ string: String) throws {
        if let streamError = streamError {
            throw streamError
        }
        let bytes = [UInt8](string.utf8)
        write(bytes, maxLength: bytes.count)
        if let streamError = streamError {
            throw streamError
        }
    }

    func write(_ data: Data) throws {
        if let streamError = streamError {
            throw streamError
        }
        if data.isEmpty {
            return
        }
        _ = data.withUnsafeBytes { (unsafeRawBuffer: UnsafeRawBufferPointer) -> UInt8 in
            if let unsafe = unsafeRawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                write(unsafe, maxLength: unsafeRawBuffer.count)
            }
            return 0
        }
        if let streamError = streamError {
            throw streamError
        }
    }
}
