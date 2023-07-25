//
//  EditMode.swift
//  Loop
//
//  Created by Noah Brauner on 7/13/23.
//  Copyright © 2023 LoopKit Authors. All rights reserved.
//

import SwiftUI

extension EditMode {
    var title: String {
        self == .active ? "Done" : "Edit"
    }
    
    mutating func toggle() {
        self = self == .active ? .inactive : .active
    }
}
