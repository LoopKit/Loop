//
//  Checkmark.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


/// A checkmark based on unit ratios of
/// {0, 20} -> {17, 0} -> {45, 43}
struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - 20 / 43 * rect.height))
            path.addLine(to: CGPoint(x: rect.minX + 17 / 45 * rect.width, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}
