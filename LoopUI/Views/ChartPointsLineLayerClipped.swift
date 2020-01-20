//
//  ChartPointsLineLayerClipped.swift
//  LoopUI
//
//  Created by Pete Schwamb on 1/20/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import SwiftCharts


class ChartPointsLineLayerClipped<T: ChartPoint>: ChartPointsLineLayer<T> {
    
    override func generateLineView(_ screenLine: ScreenLine<T>, chart: Chart) -> ChartLinesView {
        let view = super.generateLineView(screenLine, chart: chart)
        
        let lineMaskLayer = CAShapeLayer()
        var maskRect = view.frame
        maskRect.origin.y = 0
        maskRect.size.height = chart.bounds.height
        let path = CGPath(rect: maskRect, transform: nil)
        lineMaskLayer.path = path
        
        view.layer.mask = lineMaskLayer
        return view
    }

}

