//
//  DirectoryObserver.swift
//  Loop
//
//  Created by Michael Pangburn on 4/20/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation


protocol DirectoryObserver {}
typealias DirectoryObservationToken = AnyObject

extension DirectoryObserver {
    func observeDirectory(at url: URL, updatingWith notifyOfUpdates: @escaping () -> Void) -> DirectoryObservationToken? {
        return DirectoryObservation(url: url, updatingWith: notifyOfUpdates)
    }
}

private final class DirectoryObservation {
    private let fileDescriptor: CInt
    private let source: DispatchSourceFileSystemObject

    fileprivate init?(url: URL, updatingWith notifyOfUpdates: @escaping () -> Void) {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor != -1 else {
            assertionFailure("Unable to open url: \(url)")
            return nil
        }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fileDescriptor, eventMask: .all)
        source.setEventHandler(handler: notifyOfUpdates)
        source.activate()
    }

    deinit {
        source.cancel()
        close(fileDescriptor)
    }
}
