//
//  Image.swift
//  LoopUI
//
//  Created by Rick Pasetto on 6/25/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI

extension Image {
    init(frameworkImage name: String, decorative: Bool = false) {
        if decorative {
            self.init(decorative: name, bundle: Bundle.module)
        } else {
            self.init(name, bundle: Bundle.module)
        }
    }
}
