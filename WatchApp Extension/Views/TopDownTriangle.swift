//
//  TopDownTriangle.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 3/30/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


/// An isosceles triangle, pointed downward.
struct TopDownTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
