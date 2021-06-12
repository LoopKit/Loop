//
//  ClosedLoopStatus.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2021-05-28.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

class ClosedLoopStatus {
    @Published var isClosedLoop: Bool
    @Published var isClosedLoopAllowed: Bool

    init(isClosedLoop: Bool,
         isClosedLoopAllowed: Bool)
    {
        self.isClosedLoop = isClosedLoop
        self.isClosedLoopAllowed = isClosedLoopAllowed
    }
}

typealias AutomaticDosingStatus = ClosedLoopStatus
