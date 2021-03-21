//
//  DigitalCrownRotation.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 4/1/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftUI


extension View {
    func digitalCrownRotation<I: FixedWidthInteger>(
        _ binding: Binding<I>,
        over bounds: ClosedRange<I>,
        rotationsPerIncrement: Double
    ) -> some View {
        precondition(rotationsPerIncrement > 0)

        let scaledBounds = (Double(bounds.lowerBound) / rotationsPerIncrement)...(Double(bounds.upperBound) / rotationsPerIncrement)
        let scaledBinding = Binding(
            get: { Double(binding.wrappedValue) / rotationsPerIncrement },
            set: { binding.wrappedValue = I(($0 * rotationsPerIncrement).rounded()).clamped(to: bounds) }
        )
        return digitalCrownRotation(
            scaledBinding,
            from: scaledBounds.lowerBound,
            through: scaledBounds.upperBound
        )
    }

    func digitalCrownRotation<V: BinaryFloatingPoint>(
        _ binding: Binding<V>,
        over bounds: ClosedRange<V>,
        sensitivity: DigitalCrownRotationalSensitivity = .high,
        scalingRotationBy scaleFactor: V
    ) -> some View where V.Stride: BinaryFloatingPoint {
        precondition(scaleFactor > 0)

        let scaledBounds = (bounds.lowerBound * scaleFactor)...(bounds.upperBound * scaleFactor)
        let scaledBinding = Binding(
            get: { binding.wrappedValue * scaleFactor },
            set: { binding.wrappedValue = $0 / scaleFactor }
        )
        return digitalCrownRotation(
            scaledBinding,
            from: scaledBounds.lowerBound,
            through: scaledBounds.upperBound,
            sensitivity: sensitivity
        )
    }
}
