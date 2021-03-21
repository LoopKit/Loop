//
//  DeviceLifecycleProgressState.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-07-28.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit

extension DeviceLifecycleProgressState {
    public var color: UIColor {
        switch self {
        case .normalCGM:
            return .glucose
        case .normalPump:
            return .insulin
        case .warning:
            return .warning
        case .critical:
            return .critical
        }
    }
}
