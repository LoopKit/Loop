//
//  GlucoseScene.swift
//  WatchApp Extension
//
//  Created by Bharat Mediratta on 7/16/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import Foundation
import SpriteKit
import HealthKit
import LoopKit
import WatchKit

// Stashing the extensions here for ease of development, but they should likely
// move into their own files as appropriate
extension UIColor {
    static let glucoseTintColor = UIColor(red: 0 / 255, green: 176 / 255, blue: 255 / 255, alpha: 1)
    static let gridColor = UIColor(white: 193 / 255, alpha: 1)
    static let nowColor = UIColor(white: 193 / 255, alpha: 0.5)
    static let rangeColor = UIColor(red: 158/255, green: 215/255, blue: 245/255, alpha: 1)
}

extension SKLabelNode {
    static func basic(at position: CGPoint) -> SKLabelNode {
        let basic = SKLabelNode(text: "--")
        basic.fontSize = 12
        basic.fontName = "HelveticaNeue"
        basic.fontColor = .white
        basic.alpha = 0.8
        basic.verticalAlignmentMode = .top
        basic.horizontalAlignmentMode = .left
        basic.position = position
        return basic
    }
}

struct ChartData {
    var unit: HKUnit?
    var temporaryOverride: WatchDatedRange?
    var historicalGlucose: [SampleValue]?
    var predictedGlucose: [SampleValue]?
    var targetRanges: [WatchDatedRange]?
}

struct Scaler {
    let start: Date
    let bgMin: Double
    let xScale: CGFloat
    let yScale: CGFloat

    func point(_ x: Date, _ y: Double) -> CGPoint {
        return CGPoint(x: CGFloat(x.timeIntervalSince(start)) * xScale, y: CGFloat(y - bgMin) * yScale)
    }

    func rect(for range: WatchDatedRange) -> CGRect {
        let a = point(range.startDate, range.minValue)
        let b = point(range.endDate, range.maxValue)
        return CGRect(origin: a, size: CGSize(width: b.x - a.x, height: b.y - a.y))
    }
}

extension HKUnit {
    var highWatermarkRange: [Double] {
        if unitString == "mg/dL" {
            return [150.0, 200.0, 250.0, 300.0, 350.0, 400.0]
        } else {
            return [8.3,   11.1,  13.9,  16.6,  19.4,  22.2]
        }
    }

    var lowWatermark: Double {
        if unitString == "mg/dL" {
            return 50.0
        } else {
            return 2.8
        }
    }
}

class GlucoseChartScene: SKScene {
    var data: ChartData = ChartData() {
        didSet {
            needsUpdate = true
        }
    }

    var visibleBg: Int = 1 {
        didSet {
            if let range = data.unit?.highWatermarkRange, (0..<range.count).contains(visibleBg) {
                WKInterfaceDevice.current().play(.success)
                needsUpdate = true
            } else {
                visibleBg = oldValue
            }
        }
    }

    private var visibleHours: Int = 3
    private var timer: Timer?
    private var needsUpdate: Bool = true
    private var dataLayer: SKNode!
    private var hoursLabel: SKLabelNode!
    private var maxBGLabel: SKLabelNode!
    private var minBGLabel: SKLabelNode!

    override init() {
        // Use the fixed sizes specified in the storyboard, based on our guess of the model size
        var sceneSize: CGSize
        if WKInterfaceDevice.current().screenBounds.width > 136 {
            sceneSize = CGSize(width: 154, height: 86)
        } else {
            sceneSize = CGSize(width: 134, height: 110)
        }
        super.init(size: sceneSize)

        anchorPoint = CGPoint(x: 0, y: 0)
        scaleMode = .aspectFit
        backgroundColor = .clear

        let frame = SKShapeNode(rectOf: size, cornerRadius: 5)
        frame.position = CGPoint(x: size.width / 2, y: size.height / 2)
        frame.lineWidth = 2
        frame.fillColor = .clear
        frame.strokeColor = .gridColor
        addChild(frame)

        let dashedPath = CGPath(rect: CGRect(origin: CGPoint(x: size.width / 2, y: 0), size: CGSize(width: 0, height: size.height)), transform: nil).copy(dashingWithPhase: 0, lengths: [4.0, 3.0])
        let now = SKShapeNode(path: dashedPath)
        now.strokeColor = .nowColor
        addChild(now)

        hoursLabel = SKLabelNode.basic(at: CGPoint(x: 5, y: size.height - 5))
        addChild(hoursLabel)

        maxBGLabel = SKLabelNode.basic(at: CGPoint(x: size.width - 5, y: size.height - 5))
        maxBGLabel.horizontalAlignmentMode = .right
        addChild(maxBGLabel)

        minBGLabel = SKLabelNode.basic(at: CGPoint(x: size.width - 5, y: 5))
        minBGLabel.horizontalAlignmentMode = .right
        minBGLabel.verticalAlignmentMode = .bottom
        addChild(minBGLabel)

        dataLayer = SKNode()
        addChild(dataLayer)

        // Force an update once a minute
        Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes: 1), repeats: true) { _ in
            self.needsUpdate = true
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func update(_ currentTime: TimeInterval) {
        guard let unit = data.unit, needsUpdate == true else {
            return
        }

        let window = TimeInterval(hours: Double(visibleHours))
        let scaler = Scaler(start: Date() - window,
                            bgMin: unit.lowWatermark,
                            xScale: size.width / CGFloat(window * 2),
                            yScale: size.height / CGFloat(unit.highWatermarkRange[visibleBg] - unit.lowWatermark))


        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        minBGLabel.text = numberFormatter.string(from: unit.lowWatermark)
        maxBGLabel.text = numberFormatter.string(from: unit.highWatermarkRange[visibleBg])
        hoursLabel.text = "\(Int(visibleHours))h"

        dataLayer.removeAllChildren()
        if let range = data.temporaryOverride {
            let node = SKShapeNode(rect: scaler.rect(for: range))
            node.fillColor = UIColor.rangeColor.withAlphaComponent(0.4)
            node.strokeColor = .clear
            dataLayer.addChild(node)
        }

        data.targetRanges?.enumerated().forEach { (i, range) in
            let node = SKShapeNode(rect: scaler.rect(for: range))
            node.fillColor = UIColor.rangeColor.withAlphaComponent(data.temporaryOverride != nil ? 0.15 : 0.4)
            node.strokeColor = .clear
            dataLayer.addChild(node)
        }

        data.historicalGlucose?.filter { $0.startDate > scaler.start }.forEach {
            let node = SKShapeNode(circleOfRadius: 1)
            node.fillColor = .glucoseTintColor
            node.strokeColor = .glucoseTintColor
            node.position = scaler.point($0.startDate, $0.quantity.doubleValue(for: unit))
            dataLayer.addChild(node)
        }

        if let predictedGlucose = data.predictedGlucose, predictedGlucose.count > 2 {
            let predictedPath = CGMutablePath()
            predictedPath.addLines(between: predictedGlucose.map {
                scaler.point($0.startDate, $0.quantity.doubleValue(for: unit))
            })
            dataLayer.addChild(SKShapeNode(path: predictedPath.copy(dashingWithPhase: 11, lengths: [5, 3])))
        }

        needsUpdate = false
    }
}
