//
//  Image+Exists.swift
//  Loop
//
//  Created by Cameron Ingham on 10/23/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import UIKit

// Since this `Image` initializer provides the parent view with an `EmptyView` if the asset is not found in the bundle, it can double the spacing between adjacent elements in a `VStack`, `HStack`, etc.
extension Image {
    static func imageExists(
        _ name: String,
        in bundle: Bundle? = nil,
        with configuration: UIImage.Configuration? = nil
    ) -> Bool {
        UIImage(named: name, in: bundle, with: configuration) != nil
    }
}
