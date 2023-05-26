//
//  ZipArchive.swift
//  Loop
//
//  Created by Darin Krauss on 6/25/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import ZIPFoundation

public enum ZipArchiveError: Error, Equatable {
    case streamFinished
}

public class ZipArchive {

    public enum CompressionMethod {
        case none
        case deflate

        var zfMethod: ZIPFoundation.CompressionMethod {
            switch self {
            case .deflate:
                return .deflate
            case .none:
                return .none
            }
        }
    }

    public class Stream: NSObject, DataOutputStream {

        private let archive: Archive
        private let compressionMethod: CompressionMethod

        private let semaphore = DispatchSemaphore(value: 0)
        private let processingQueue: DispatchQueue

        private let chunks = Locked<[Data]>([])
        private let error = Locked<Error?>(nil)
        private let finished = Locked<Bool>(false)

        fileprivate init(archive: Archive, path: String, compressionMethod: CompressionMethod) {
            self.archive = archive
            self.compressionMethod = compressionMethod
            processingQueue = DispatchQueue(label: "org.loopkit.Loop.zipArchive." + path)
            super.init()
            startProcessing(path)
        }

        public var streamError: Error? {
            return error.value
        }

        private func startProcessing(_ path: String) {
            processingQueue.async {
                do {
                    try self.archive.addEntry(with: path, type: .file, compressionMethod: self.compressionMethod.zfMethod) { position, size in
                        self.semaphore.wait()
                        var chunk: Data!
                        self.chunks.mutate { (value) in
                            if value.count > 0 {
                                chunk = value.removeFirst()
                            } else if self.finished.value {
                                chunk = Data()
                            }
                        }
                        return chunk
                    }
                } catch {
                    self.error.mutate { value in
                        value = error
                    }
                }
            }
        }

        // MARK: - DataOutputStream
        public func write(_ data: Data) throws {
            if let error = error.value {
                throw error
            }
            if finished.value {
                throw ZipArchiveError.streamFinished
            }
            chunks.mutate { value in
                value.append(data)
            }
            semaphore.signal()
        }

        public func finish(sync: Bool) throws {
            // An empty Data() is the sigil for the ZipFoundation read callback
            // to detect end of stream.
            finished.value = true
            semaphore.signal()
            if sync {
                // Block until processingQueue is finished, and then check error state
                processingQueue.sync(flags: .barrier) { }
                if let error = error.value {
                    throw error
                }
            }
        }
    }

    private var closed: Bool = false
    private let archive: Archive
    private var stream: Stream?
    private var error: Error?

    private let lock = UnfairLock()

    public init?(url: URL) {
        guard let archive = Archive(url: url, accessMode: .create) else {
            return nil
        }
        self.archive = archive
    }

    public func createArchiveFile(withPath path: String, compressionMethod: CompressionMethod = .deflate) -> DataOutputStream {
        return lock.withLock {
            try? stream?.finish(sync: true)
            stream = Stream(archive: archive, path: path, compressionMethod: compressionMethod)
            return stream!
        }
    }

    public func createArchiveFile(withPath path: String, contentsOf url: URL, compressionMethod: CompressionMethod = .deflate) -> Error? {
        let data: Data

        do {
            data = try Data(contentsOf: url)
        } catch let error {
            return error
        }

        let stream = createArchiveFile(withPath: path, compressionMethod: compressionMethod)
        try? stream.write(data)

        return lock.withLock { error }
    }

    @discardableResult
    public func close() -> Error? {
        return lock.withLock {
            if closed {
                return nil
            }
            defer { closed = true }
            do {
                try stream?.finish(sync: true)
            } catch {
                setError(error)
            }
            return error
        }
    }

    private func setError(_ err: Error) {
        guard error == nil else {
            return
        }
        error = err
    }
}
