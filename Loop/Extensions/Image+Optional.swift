//
//  Image+Optional.swift
//  Loop
//
//  Created by Cameron Ingham on 1/7/25.
//  Copyright © 2025 LoopKit Authors. All rights reserved.
//

import SwiftUI

// Since this `Image` initializer provides a view even if the asset is not found in the bundle, it can double the spacing between adjacent elements in a `VStack`, `HStack`, etc.
extension Image {
    init?(_ name: String, bundle: Bundle? = nil) {
        if let _ = UIImage(named: name, in: bundle, with: nil) {
            self = Image(name, bundle: bundle)
        } else {
            return nil
        }
    }
}
