//
//  AutomaticDosingStatus.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2021-05-28.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

class AutomaticDosingStatus {
    @Published var automaticDosingEnabled: Bool
    @Published var isAutomaticDosingAllowed: Bool

    init(automaticDosingEnabled: Bool,
         isAutomaticDosingAllowed: Bool)
    {
        self.automaticDosingEnabled = automaticDosingEnabled
        self.isAutomaticDosingAllowed = isAutomaticDosingAllowed
    }
}
