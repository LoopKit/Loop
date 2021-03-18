//
//  DeviceLifecycleProgressState.swift
//  LoopUI
//
//  Created by Nathaniel Hamming on 2020-07-28.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import SwiftUI

extension DeviceLifecycleProgressState {
    public var color: UIColor {
        switch self {
        case .critical:
            return .critical
        case .dimmed:
            if #available(iOS 14.0, *) {
                return UIColor(Color.secondary)
            } else {
                return .systemGray
            }
        case .normalCGM:
            return .glucose
        case .normalPump:
            return .insulin
        case .warning:
            return .warning
        }
    }
}
