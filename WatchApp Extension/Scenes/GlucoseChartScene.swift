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

class GlucoseChartScene: SKScene {
    let log = OSLog(category: "GlucoseChartScene")

    var textInsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)

    var data: GlucoseChartData? {
        didSet {
            if let firstNewValue = data?.predictedGlucose?.first {
                if oldValue?.predictedGlucose?.first == nil || oldValue?.predictedGlucose?.first!.startDate != firstNewValue.startDate {
                    shouldAnimatePredictionPath = true
                }
            }
        }
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
        return children.contains(where: { $0.hasActions() })
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
        if let existingNode = nodes[hashValue] {
            return (sprite: existingNode, created: false)
        } else {
            let newNode = SKSpriteNode(color: .clear, size: CGSize(width: 0, height: 0))
            newNode.anchorPoint = CGPoint(x: 0, y: 0)
            nodes[hashValue] = newNode
            addChild(newNode)
            return (sprite: newNode, created: true)
        }
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
        guard let data = data, let unit = data.unit else {
            return
        }

        let spannedInterval = DateInterval(start: Date() - visibleDuration / 2, duration: visibleDuration)
        let glucoseRange = data.chartableGlucoseRange(from: spannedInterval)
        let scaler = GlucoseChartScaler(size: size, dateInterval: spannedInterval, glucoseRange: glucoseRange, unit: unit, coordinateSystem: .inverted)

        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        minBGLabel.text = numberFormatter.string(from: glucoseRange.lowerBound.doubleValue(for: unit))
        maxBGLabel.text = numberFormatter.string(from: glucoseRange.upperBound.doubleValue(for: unit))
        hoursLabel.text = dateFormatter.string(from: visibleDuration)

        // Keep track of the nodes we started this pass with so we can expire obsolete nodes at the end
        var inactiveNodes = nodes

        let activeOverride = data.correctionRange?.activeOverride

        data.correctionRange?.quantityBetween(start: spannedInterval.start, end: spannedInterval.end).forEach { range in
            let (sprite, created) = getSprite(forHash: range.chartHashValue)
            sprite.color = UIColor.glucose.withAlphaComponent(activeOverride != nil ? 0.2 : 0.3)
            sprite.zPosition = NodePlane.ranges.zPosition
            sprite.move(to: scaler.rect(for: range, unit: unit), animated: !created)
            inactiveNodes.removeValue(forKey: range.chartHashValue)
        }

        // Make temporary overrides visually match what we do in the Loop app. This means that we have
        // one darker box which represents the duration of the override, but we have a second lighter box which
        // extends to the end of the visible window.
        if let range = activeOverride {
            let (sprite1, created) = getSprite(forHash: range.chartHashValue)
            sprite1.color = UIColor.glucose.withAlphaComponent(0.4)
            sprite1.zPosition = NodePlane.overrideRanges.zPosition
            sprite1.move(to: scaler.rect(for: range, unit: unit), animated: !created)
            inactiveNodes.removeValue(forKey: range.chartHashValue)

            if range.end < spannedInterval.end {
                let extendedRange = GlucoseRangeSchedule.Override(context: range.context, start: range.start, end: spannedInterval.end, value: range.value)
                let (sprite2, created) = getSprite(forHash: extendedRange.chartHashValue)
                sprite2.color = UIColor.glucose.withAlphaComponent(0.25)
                sprite2.zPosition = NodePlane.overrideRanges.zPosition
                sprite2.move(to: scaler.rect(for: extendedRange, unit: unit), animated: !created)
                inactiveNodes.removeValue(forKey: extendedRange.chartHashValue)
            }
        }

        data.historicalGlucose?.filter { scaler.dates.contains($0.startDate) }.forEach {
            let center = scaler.point($0.startDate, $0.quantity.doubleValue(for: unit))
            let size = CGSize(width: 2, height: 2)
            let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
            let (sprite, created) = getSprite(forHash: $0.chartHashValue)
            sprite.color = .glucose
            sprite.zPosition = NodePlane.values.zPosition
            sprite.move(to: CGRect(origin: origin, size: size).alignedToScreenScale(WKInterfaceDevice.current().screenScale), animated: !created)
            inactiveNodes.removeValue(forKey: $0.chartHashValue)
        }

        predictedPathNode?.removeFromParent()
        if let predictedGlucose = data.predictedGlucose, predictedGlucose.count > 2 {
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
