//
//  Environment+Dismiss.swift
//  Loop
//
//  Created by Michael Pangburn on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


private struct PresentationDismissalKey: EnvironmentKey {
    static let defaultValue = {}
}


extension EnvironmentValues {
    var dismiss: () -> Void {
        get { self[PresentationDismissalKey.self] }
        set { self[PresentationDismissalKey.self] = newValue }
    }
}
