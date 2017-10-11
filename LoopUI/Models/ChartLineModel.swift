//
//  ChartLineModel.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import SwiftCharts


extension ChartLineModel {
    /// Creates a model configured with the dashed prediction line style
    ///
    /// - Parameters:
    ///   - points: The points to construct the line
    ///   - color: The line color
    ///   - width: The line width
    /// - Returns: A new line model
    static func predictionLine(points: [T], color: UIColor, width: CGFloat) -> ChartLineModel {
        // TODO: Bug in ChartPointsLineLayer requires a non-zero animation to draw the dash pattern
        return self.init(chartPoints: points, lineColor: color, lineWidth: width, animDuration: 0.0001, animDelay: 0, dashPattern: [6, 5])
    }
}
