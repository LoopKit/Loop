//
//  Microbolus.swift
//  LoopCore
//
//  Created by Ivan Valkou on 07.11.2019.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import Foundation

public enum Microbolus {
    public enum SafeMode: Int, CaseIterable {
        case enabled
        case limited
        case disabled

        public static var allCases: [SafeMode] {
            [.enabled, .limited, .disabled]
        }
    }
}
