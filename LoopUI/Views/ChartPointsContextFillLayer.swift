//
//  ChartPointsContextFillLayer.swift
//  Loop
//
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import SwiftCharts


struct ChartPointsFill {
    let chartPoints: [ChartPoint]
    let fillColor: UIColor
    let createContainerPoints: Bool
    let blendMode: CGBlendMode
    fileprivate var screenPoints: [CGPoint] = []

    init?(chartPoints: [ChartPoint], fillColor: UIColor, createContainerPoints: Bool = true, blendMode: CGBlendMode = .normal) {
        guard chartPoints.count > 1 else {
            return nil;
        }

        var chartPoints = chartPoints

        if createContainerPoints {
            // Create a container line at value position 0
            if let first = chartPoints.first {
                chartPoints.insert(ChartPoint(x: first.x, y: ChartAxisValueInt(0)), at: 0)
            }

            if let last = chartPoints.last {
                chartPoints.append(ChartPoint(x: last.x, y: ChartAxisValueInt(0)))
            }
        }

        self.chartPoints = chartPoints
        self.fillColor = fillColor
        self.createContainerPoints = createContainerPoints
        self.blendMode = blendMode
    }

    var areaPath: UIBezierPath {
        let path = UIBezierPath()

        if let point = screenPoints.first {
            path.move(to: point)
        }

        for point in screenPoints.dropFirst() {
            path.addLine(to: point)
        }

        return path
    }
}


final class ChartPointsFillsLayer: ChartCoordsSpaceLayer {
    let fills: [ChartPointsFill]

    init?(xAxis: ChartAxis, yAxis: ChartAxis, fills: [ChartPointsFill?]) {
        self.fills = fills.compactMap({ $0 })

        guard fills.count > 0 else {
            return nil
        }

        super.init(xAxis: xAxis, yAxis: yAxis)
    }

    override func chartInitialized(chart: Chart) {
        super.chartInitialized(chart: chart)

        let view = ChartPointsFillsView(
            frame: chart.bounds,
            chartPointsFills: fills.map { (fill) -> ChartPointsFill in
                var fill = fill

                fill.screenPoints = fill.chartPoints.map { (point) -> CGPoint in
                    return modelLocToScreenLoc(x: point.x.scalar, y: point.y.scalar)
                }

                return fill
            }
        )

        chart.addSubview(view)
    }
}


class ChartPointsFillsView: UIView {
    let chartPointsFills: [ChartPointsFill]
    var allowsAntialiasing = false

    init(frame: CGRect, chartPointsFills: [ChartPointsFill]) {
        self.chartPointsFills = chartPointsFills

        super.init(frame: frame)

        backgroundColor = .clear
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.saveGState()
        context.setAllowsAntialiasing(allowsAntialiasing)

        for fill in chartPointsFills {
            context.setFillColor(fill.fillColor.cgColor)
            fill.areaPath.fill(with: fill.blendMode, alpha: 1)
        }

        context.restoreGState()
    }
}
