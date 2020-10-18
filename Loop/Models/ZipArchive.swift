//
//  ZipArchive.swift
//  Loop
//
//  Created by Darin Krauss on 6/25/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import LoopKit
import Minizip

public enum ZipArchiveError: Error, Equatable {
    case unexpectedStatus(Stream.Status)
    case internalFailure(Int32)
}

public class ZipArchive {
    public enum Compression: Int {
        case none
        case bestSpeed
        case bestCompression
        case `default`

        fileprivate var zCompression: Int32 {
            switch self {
            case .none:
                return Z_NO_COMPRESSION
            case .bestSpeed:
                return Z_BEST_SPEED
            case .bestCompression:
                return Z_BEST_COMPRESSION
            case .default:
                return Z_DEFAULT_COMPRESSION
            }
        }
    }

    public class Stream: OutputStream, StreamDelegate {
        private let archive: ZipArchive
        private let path: String
        private let compression: Compression
        private var status: Status {
            didSet {
                if let event = status.event {
                    synchronizedDelegate.notify { $0?.stream?(self, handle: event) }
                }
            }
        }

        private var synchronizedDelegate = WeakSynchronizedDelegate<StreamDelegate>()

        fileprivate init(archive: ZipArchive, path: String, compression: Compression) {
            self.archive = archive
            self.path = path
            self.compression = compression
            self.status = archive.closed ? .closed : archive.error != nil ? .error : .notOpen
            super.init(toMemory: ())
        }

        // MARK: - Stream
        public override func open() {
            lock.withLock {
                guard transitionStatus(from: .notOpen, to: .opening) else {
                    return
                }

                var zipFileInfo = zip_fileinfo(tmz_date: Date().zip, dosDate: 0, internal_fa: 0, external_fa: 0)
                setErrorIfZipFailure(zipOpenNewFileInZip(archive.file, path, &zipFileInfo, nil, 0, nil, 0, nil, Z_DEFLATED, compression.zCompression))
                guard error == nil else {
                    return
                }

                _ = transitionStatus(from: .opening, to: .open)
            }
        }

        public override func close() {
            lock.withLock {
                unlockedClose()
            }
        }

        public override var delegate: StreamDelegate? {
            get {
                return synchronizedDelegate.delegate
            }
            set {
                synchronizedDelegate.delegate = newValue ?? self
            }
        }

        public override func property(forKey key: Stream.PropertyKey) -> Any? { nil }

        public override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool { false }

        public override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) { fatalError("not implemented") }

        public override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) { fatalError("not implemented") }

        public override var streamStatus: Status { lock.withLock { status } }

        public override var streamError: Error? { lock.withLock { error } }

        // MARK: - OutputStream

        public override func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
            return lock.withLock {
                guard transitionStatus(from: .open, to: .writing) else {
                    return -1
                }

                setErrorIfZipFailure(zipWriteInFileInZip(archive.file, buffer, UInt32(len)))
                guard error == nil else {
                    return -1
                }

                guard transitionStatus(from: .writing, to: .open) else {
                    return -1
                }

                return len
            }
        }

        public override var hasSpaceAvailable: Bool { true }

        // MARK: - Internal

        fileprivate func unlockedClose() {
            _ = transitionStatus(from: .open, to: .closed)
            setErrorIfZipFailure(zipCloseFileInZip(archive.file))
            archive.stream = nil
        }

        private func transitionStatus(from: Status, to: Status) -> Bool {
            guard status == from else {
                setError(ZipArchiveError.unexpectedStatus(status))
                return false
            }
            status = to
            return true
        }

        private func setErrorIfZipFailure(_ err: Int32) {
            guard err != ZIP_OK else {
                return
            }
            setError(ZipArchiveError.internalFailure(err))
        }

        private func setError(_ err: Error) {
            status = .error
            archive.setError(err)
        }

        private var error: Error? { archive.error }

        private var lock: UnfairLock { archive.lock }
    }

    private var closed: Bool
    private var file: zipFile
    private var stream: Stream?
    private var error: Error?

    private let lock = UnfairLock()

    public init?(url: URL) {
        guard let file = zipOpen(url.path, APPEND_STATUS_CREATE) else {
            return nil
        }
        self.closed = false
        self.file = file
    }

    public func createArchiveFile(withPath path: String, compression: Compression = .default) -> OutputStream {
        return lock.withLock {
            stream?.unlockedClose()
            stream = Stream(archive: self, path: path, compression: compression)
            return stream!
        }
    }

    public func createArchiveFile(withPath path: String, contentsOf url: URL, compression: Compression = .default) -> Error? {
        let data: Data

        do {
            data = try Data(contentsOf: url)
        } catch let error {
            return error
        }

        let stream = createArchiveFile(withPath: path, compression: compression)
        stream.open()
        try? stream.write(data)
        stream.close()

        return lock.withLock { error }
    }

    @discardableResult
    public func close() -> Error? {
        return lock.withLock {
            if closed {
                return nil
            }
            defer { closed = true }
            stream?.unlockedClose()
            setErrorIfZipFailure(zipClose(file, nil))
            return error
        }
    }

    private func setErrorIfZipFailure(_ err: Int32) {
        guard err != ZIP_OK else {
            return
        }
        setError(ZipArchiveError.internalFailure(err))
    }

    private func setError(_ err: Error) {
        guard error == nil else {
            return
        }
        error = err
    }
}

extension Stream.Status: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch self {
        case .notOpen:
            return "notOpen"
        case .opening:
            return "opening"
        case .open:
            return "open"
        case .reading:
            return "reading"
        case .writing:
            return "writing"
        case .atEnd:
            return "atEnd"
        case .closed:
            return "closed"
        case .error:
            return "error"
        @unknown default:
            return "unknown"
        }
    }
}

fileprivate extension Stream.Status {
    var event: Stream.Event? {
        switch self {
        case .open:
            return .openCompleted
        case .error:
            return .errorOccurred
        default:
            return nil
        }
    }
}

fileprivate extension Date {
    var zip: tm_zip {
        let calendar = Calendar.current
        let date = self
        return tm_zip(tm_sec: UInt32(calendar.component(.second, from: date)),
                      tm_min: UInt32(calendar.component(.minute, from: date)),
                      tm_hour: UInt32(calendar.component(.hour, from: date)),
                      tm_mday: UInt32(calendar.component(.day, from: date)),
                      tm_mon: UInt32(calendar.component(.month, from: date)),
                      tm_year: UInt32(calendar.component(.year, from: date)))
    }
}
