//
//  MockUploadEventListener.swift
//  LoopTests
//
//  Created by Pete Schwamb on 11/30/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import Foundation
@testable import Loop

class MockUploadEventListener: UploadEventListener {
    var lastUploadTriggeringType: RemoteDataType?
    func triggerUpload(for triggeringType: RemoteDataType) {
        self.lastUploadTriggeringType = triggeringType
    }
}
