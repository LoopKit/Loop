//
//  LoopChartView.swift
//  Loop
//
//  Created by Noah Brauner on 7/25/24.
//  Copyright © 2024 LoopKit Authors. All rights reserved.
//

import SwiftUI
import LoopKitUI

struct LoopChartView<Chart: ChartProviding>: UIViewRepresentable {
    let chartManager: ChartsManager
    let dateInterval: DateInterval
    @Binding var isInteractingWithChart: Bool
    var configuration = { (view: Chart) in }

    func makeUIView(context: Context) -> ChartContainerView {
        guard let chartIndex = chartManager.charts.firstIndex(where: { $0 is Chart }) else {
            fatalError("Expected exactly one matching chart in ChartsManager")
        }
        
        let view = ChartContainerView()
        view.chartGenerator = { [chartManager] frame in
            chartManager.chart(atIndex: chartIndex, frame: frame)?.view
        }

        let gestureRecognizer = UILongPressGestureRecognizer()
        gestureRecognizer.minimumPressDuration = 0.1
        gestureRecognizer.addTarget(context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(gestureRecognizer)

        return view
    }

    func updateUIView(_ chartContainerView: ChartContainerView, context: Context) {
        guard let chartIndex = chartManager.charts.firstIndex(where: { $0 is Chart }),
              let chart = chartManager.charts[chartIndex] as? Chart else {
                  fatalError("Expected exactly one matching chart in ChartsManager")
        }
        
        chartManager.invalidateChart(atIndex: chartIndex)
        chartManager.startDate = dateInterval.start
        chartManager.maxEndDate = dateInterval.end
        chartManager.updateEndDate(dateInterval.end)
        configuration(chart)
        chartManager.prerender()
        chartContainerView.reloadChart()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator {
        var parent: LoopChartView

        init(_ parent: LoopChartView) {
            self.parent = parent
        }
        
        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                parent.chartManager.gestureRecognizer = recognizer
                withAnimation(.easeInOut(duration: 0.2)) {
                    parent.isInteractingWithChart = true
                }
            case .cancelled, .ended, .failed:
                // Workaround: applying the delay on the animation directly does not delay the disappearance of the touch indicator.
                // FIXME: No animation is applied to the disappearance of the touch indicator; it simply disappears.
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                    withAnimation(.easeInOut(duration: 0.5)) {
                        self?.parent.isInteractingWithChart = false
                    }
                }
            default:
                break
            }
        }
    }
}
