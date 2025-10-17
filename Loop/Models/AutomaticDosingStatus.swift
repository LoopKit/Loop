//
//  AutomaticDosingStatus.swift
//  Loop
//
//  Created by Nathaniel Hamming on 2021-05-28.
//  Copyright © 2021 LoopKit Authors. All rights reserved.
//

import Foundation

@Observable
public class AutomaticDosingStatus: Codable {
    public var automaticDosingEnabled: Bool
    
    public init(automaticDosingEnabled: Bool) {
        self.automaticDosingEnabled = automaticDosingEnabled
    }
}
