//
//  GlucoseChartScene.swift
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
import os.log

private enum NodePlane: Int {
    case lines = 0
    case ranges
    case overrideRanges
    case values
    case labels

    var zPosition: CGFloat {
        return CGFloat(rawValue)
    }
}

private extension SKLabelNode {
    static func basic(at position: CGPoint) -> SKLabelNode {
        let basic = SKLabelNode(text: "--")
        basic.fontSize = UIFont.preferredFont(forTextStyle: .caption2).pointSize
        basic.fontName = "HelveticaNeue"
        basic.fontColor = .chartLabel
        basic.alpha = 0.8
        basic.verticalAlignmentMode = .top
        basic.horizontalAlignmentMode = .left
        basic.position = position
        basic.zPosition = NodePlane.labels.zPosition
        return basic
    }
}

private extension SKSpriteNode {
    func move(to rect: CGRect, animated: Bool) {
        if parent == nil || animated == false || (size.equalTo(rect.size) && position.equalTo(rect.origin)) {
            size = rect.size
            position = rect.origin
        } else {
            run(.group([
                .move(to: rect.origin, duration: 0.25),
                .resize(toWidth: rect.size.width, duration: 0.25),
                .resize(toHeight: rect.size.height, duration: 0.25)
            ]))
        }
    }
}

extension CGRect {
    fileprivate func alignedToScreenScale(_ screenScale: CGFloat) -> CGRect {
        let factor = 1 / screenScale

        return CGRect(
            x: origin.x.floored(to: factor),
            y: origin.y.floored(to: factor),
            width: size.width.ceiled(to: factor),
            height: size.height.ceiled(to: factor)
        )
    }
}

private struct Scaler {
    let dates: DateInterval
    let glucoseMin: Double
    let xScale: CGFloat
    let yScale: CGFloat

    func point(_ x: Date, _ y: Double) -> CGPoint {
        return CGPoint(x: CGFloat(x.timeIntervalSince(dates.start)) * xScale, y: CGFloat(y - glucoseMin) * yScale)
    }

    // By default enforce a minimum height so that the range is visible
    func rect(for range: GlucoseChartValueHashable, unit: HKUnit, minHeight: CGFloat = 2) -> CGRect {
        let minY: Double
        let maxY: Double

        if unit != .milligramsPerDeciliter {
            minY = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: range.min).doubleValue(for: unit)
            maxY = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: range.max).doubleValue(for: unit)
        } else {
            minY = range.min
            maxY = range.max
        }

        let a = point(max(dates.start, range.start), minY)
        let b = point(min(dates.end, range.end), maxY)
        let size = CGSize(width: b.x - a.x, height: max(b.y - a.y, minHeight))
        return CGRect(origin: CGPoint(x: a.x + size.width / 2, y: a.y + size.height / 2), size: size).alignedToScreenScale(WKInterfaceDevice.current().screenScale)
    }
}

private extension HKUnit {
    var axisIncrement: Double {
        return chartableIncrement * 25
    }

    var highWatermark: Double {
        if self == .milligramsPerDeciliter {
            return 150
        } else {
            return 8
        }
    }

    var lowWatermark: Double {
        if self == .milligramsPerDeciliter {
            return 50.0
        } else {
            return 3.0
        }
    }
}

class GlucoseChartScene: SKScene {
    let log = OSLog(category: "GlucoseChartScene")

    var textInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)

    var unit: HKUnit?
    var correctionRange: GlucoseRangeSchedule?
    var historicalGlucose: [SampleValue]? {
        didSet {
            historicalGlucoseRange = historicalGlucose?.quantityRange
        }
    }
    private(set) var historicalGlucoseRange: Range<HKQuantity>?
    var predictedGlucose: [SampleValue]? {
        didSet {
            predictedGlucoseRange = predictedGlucose?.quantityRange

            if let firstNewValue = predictedGlucose?.first {
                if oldValue?.first == nil || oldValue?.first!.startDate != firstNewValue.startDate {
                    shouldAnimatePredictionPath = true
                }
            }
        }
    }
    private(set) var predictedGlucoseRange: Range<HKQuantity>?

    private func chartableGlucoseRange(from start: Date, to end: Date) -> Range<HKQuantity> {
        let unit = self.unit ?? .milligramsPerDeciliter

        // Defaults
        var min = unit.lowWatermark
        var max = unit.highWatermark

        for correction in correctionRange?.quantityBetween(start: start, end: end) ?? [] {
            min = Swift.min(min, correction.value.lowerBound.doubleValue(for: unit))
            max = Swift.max(max, correction.value.upperBound.doubleValue(for: unit))
        }

        if let override = correctionRange?.activeOverrideQuantityRange {
            min = Swift.min(min, override.lowerBound.doubleValue(for: unit))
            max = Swift.max(max, override.upperBound.doubleValue(for: unit))
        }

        if let historicalGlucoseRange = historicalGlucoseRange {
            min = Swift.min(min, historicalGlucoseRange.lowerBound.doubleValue(for: unit))
            max = Swift.max(max, historicalGlucoseRange.upperBound.doubleValue(for: unit))
        }

        if let predictedGlucoseRange = predictedGlucoseRange {
            min = Swift.min(min, predictedGlucoseRange.lowerBound.doubleValue(for: unit))
            max = Swift.max(max, predictedGlucoseRange.upperBound.doubleValue(for: unit))
        }

        min = min.floored(to: unit.axisIncrement)
        max = max.ceiled(to: unit.axisIncrement)

        let lowerBound = HKQuantity(unit: unit, doubleValue: min)
        let upperBound = HKQuantity(unit: unit, doubleValue: max)

        return lowerBound..<upperBound
    }

    var visibleDuration = TimeInterval(hours: 6) {
        didSet {
            setNeedsUpdate()
        }
    }
    private var hoursLabel: SKLabelNode!
    private var maxBGLabel: SKLabelNode!
    private var minBGLabel: SKLabelNode!
    private var nodes: [Int: SKSpriteNode] = [:]
    private var predictedPathNode: SKShapeNode?

    private var needsUpdate = true
    private var shouldAnimatePredictionPath = false

    private lazy var dateFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    override init() {
        // Use the fixed sizes specified in the storyboard, based on our guess of the model size
        let screen = WKInterfaceDevice.current().screenBounds
        let width = screen.width - 2 /* insets */
        let height: CGFloat

        switch width {
        case let x where x < 150:  // 38mm
            height = 68
        case let x where x > 180:  // 44mm
            height = 106
        default:
            height = 86
        }

        super.init(size: CGSize(width: screen.width, height: height))
    }

    override func sceneDidLoad() {
        super.sceneDidLoad()

        anchorPoint = CGPoint(x: 0, y: 0)
        scaleMode = .resizeFill
        backgroundColor = .chartPlatter

        let dashedPath = CGPath(rect: CGRect(origin: CGPoint(x: size.width / 2, y: 0), size: CGSize(width: 0, height: size.height)), transform: nil).copy(dashingWithPhase: 0, lengths: [4.0, 3.0])
        let now = SKShapeNode(path: dashedPath)
        now.strokeColor = .chartNowLine
        now.zPosition = NodePlane.lines.zPosition
        addChild(now)

        hoursLabel = SKLabelNode.basic(at: CGPoint(x: textInsets.left, y: size.height - textInsets.top))
        addChild(hoursLabel)

        maxBGLabel = SKLabelNode.basic(at: CGPoint(x: size.width - textInsets.right, y: size.height - textInsets.top))
        maxBGLabel.horizontalAlignmentMode = .right
        addChild(maxBGLabel)

        minBGLabel = SKLabelNode.basic(at: CGPoint(x: size.width - textInsets.right, y: textInsets.bottom))
        minBGLabel.horizontalAlignmentMode = .right
        minBGLabel.verticalAlignmentMode = .bottom
        addChild(minBGLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func update(_ currentTime: TimeInterval) {
        log.default("update(_:)")

        if needsUpdate {
            needsUpdate = false
            performUpdate(animated: true)
        }
    }

    private var childNodesHaveActions: Bool {
        var childNodesHaveActions = false

        for node in children {
            if node.hasActions() {
                childNodesHaveActions = true
                break
            }
        }

        return childNodesHaveActions
    }

    override func didFinishUpdate() {
        let isPaused = self.isPaused
        let childNodesHaveActions = self.childNodesHaveActions
        log.default("didFinishUpdate() needsUpdate: %d isPaused: %d childNodesHaveActions: %d", needsUpdate, isPaused, childNodesHaveActions)

        super.didFinishUpdate()

        if !needsUpdate && !isPaused && !childNodesHaveActions {
            log.default("didFinishUpdate() pausing")
            self.isPaused = true
        }
    }

    private func getSprite(forHash hashValue: Int) -> (sprite: SKSpriteNode, created: Bool) {
        var created = false
        if nodes[hashValue] == nil {
            nodes[hashValue] = SKSpriteNode(color: .clear, size: CGSize(width: 0, height: 0))
            addChild(nodes[hashValue]!)
            created = true
        }
        return (sprite: nodes[hashValue]!, created: created)
    }

    func setNeedsUpdate() {
        dispatchPrecondition(condition: .onQueue(.main))
        needsUpdate = true

        if isPaused {
            log.default("setNeedsUpdate() unpausing")
            isPaused = false
        }
    }

    private func performUpdate(animated: Bool) {
        guard let unit = unit else {
            return
        }

        let window = visibleDuration / 2
        let start = Date(timeIntervalSinceNow: -window)
        let end = start.addingTimeInterval(visibleDuration)
        let yRange = chartableGlucoseRange(from: start, to: end)
        let scaler = Scaler(
            dates: DateInterval(start: start, end: end),
            glucoseMin: yRange.lowerBound.doubleValue(for: unit),
            xScale: size.width / CGFloat(window * 2),
            yScale: size.height / CGFloat(yRange.upperBound.doubleValue(for: unit) - yRange.lowerBound.doubleValue(for: unit))
        )

        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        minBGLabel.text = numberFormatter.string(from: yRange.lowerBound.doubleValue(for: unit))
        maxBGLabel.text = numberFormatter.string(from: yRange.upperBound.doubleValue(for: unit))
        hoursLabel.text = dateFormatter.string(from: visibleDuration)

        // Keep track of the nodes we started this pass with so we can expire obsolete nodes at the end
        var inactiveNodes = nodes

        let activeOverride = correctionRange?.activeOverride

        correctionRange?.quantityBetween(start: start, end: end).forEach({ (range) in
            let (sprite, created) = getSprite(forHash: range.chartHashValue)
            sprite.color = UIColor.glucose.withAlphaComponent(activeOverride != nil ? 0.2 : 0.3)
            sprite.zPosition = NodePlane.ranges.zPosition
            sprite.move(to: scaler.rect(for: range, unit: unit), animated: !created)
            inactiveNodes.removeValue(forKey: range.chartHashValue)
        })

        // Make temporary overrides visually match what we do in the Loop app. This means that we have
        // one darker box which represents the duration of the override, but we have a second lighter box which
        // extends to the end of the visible window.
        if let range = activeOverride {
            let (sprite1, created) = getSprite(forHash: range.chartHashValue)
            sprite1.color = UIColor.glucose.withAlphaComponent(0.4)
            sprite1.zPosition = NodePlane.overrideRanges.zPosition
            sprite1.move(to: scaler.rect(for: range, unit: unit), animated: !created)
            inactiveNodes.removeValue(forKey: range.chartHashValue)

            if range.end < end {
                let extendedRange = GlucoseRangeSchedule.Override(context: range.context, start: range.start, end: end, value: range.value)
                let (sprite2, created) = getSprite(forHash: extendedRange.chartHashValue)
                sprite2.color = UIColor.glucose.withAlphaComponent(0.25)
                sprite2.zPosition = NodePlane.overrideRanges.zPosition
                sprite2.move(to: scaler.rect(for: extendedRange, unit: unit), animated: !created)
                inactiveNodes.removeValue(forKey: extendedRange.chartHashValue)
            }
        }

        historicalGlucose?.filter { scaler.dates.contains($0.startDate) }.forEach {
            let origin = scaler.point($0.startDate, $0.quantity.doubleValue(for: unit))
            let size = CGSize(width: 2, height: 2)
            let (sprite, created) = getSprite(forHash: $0.chartHashValue)
            sprite.color = .glucose
            sprite.zPosition = NodePlane.values.zPosition
            sprite.move(to: CGRect(origin: origin, size: size).alignedToScreenScale(WKInterfaceDevice.current().screenScale), animated: !created)
            inactiveNodes.removeValue(forKey: $0.chartHashValue)
        }

        predictedPathNode?.removeFromParent()
        if let predictedGlucose = predictedGlucose, predictedGlucose.count > 2 {
            let predictedPath = CGMutablePath()
            predictedPath.addLines(between: predictedGlucose.map {
                scaler.point($0.startDate, $0.quantity.doubleValue(for: unit))
            })

            predictedPathNode = SKShapeNode(path: predictedPath.copy(dashingWithPhase: 11, lengths: [5, 3]))
            predictedPathNode?.zPosition = NodePlane.values.zPosition
            addChild(predictedPathNode!)

            if shouldAnimatePredictionPath {
                shouldAnimatePredictionPath = false
                // SKShapeNode paths cannot be easily animated. Make it vanish, then fade in at the new location.
                predictedPathNode!.alpha = 0
                predictedPathNode!.run(.sequence([
                        .wait(forDuration: 0.25),
                        .fadeIn(withDuration: 0.75)
                    ]),
                    withKey: "move"
                )
            }
        }

        // Any inactive nodes can be safely removed
        inactiveNodes.forEach { hash, node in
            node.removeFromParent()
            nodes.removeValue(forKey: hash)
        }
    }
}
