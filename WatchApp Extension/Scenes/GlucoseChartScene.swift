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
import UIKit


// Stashing the extensions here for ease of development, but they should likely
// move into their own files as appropriate
extension UIColor {
    static let glucoseTintColor = UIColor(red: 0 / 255, green: 176 / 255, blue: 255 / 255, alpha: 1)
    static let gridColor = UIColor(white: 193 / 255, alpha: 1)
    static let nowColor = UIColor(white: 0.4, alpha: 1)
    static let rangeColor = UIColor(red: 158/255, green: 215/255, blue: 245/255, alpha: 1)
    static let backgroundColor = UIColor(white: 0.15, alpha: 1)
}

extension SKLabelNode {
    static func basic(at position: CGPoint) -> SKLabelNode {
        let basic = SKLabelNode(text: "--")
        basic.fontSize = 15
        basic.fontName = "HelveticaNeue"
        basic.fontColor = .white
        basic.alpha = 0.8
        basic.verticalAlignmentMode = .top
        basic.horizontalAlignmentMode = .left
        basic.position = position
        return basic
    }
}

extension SKSpriteNode {
    func move(to rect: CGRect, animated: Bool) {
        if parent == nil || animated == false {
            size = rect.size
            position = rect.origin
        } else {
            run(SKAction.group([
                SKAction.move(to: rect.origin, duration: 0.25),
                SKAction.resize(toWidth: rect.size.width, duration: 0.25),
                SKAction.resize(toHeight: rect.size.height, duration: 0.25)]))
        }
    }
}

struct Scaler {
    let startDate: Date
    let glucoseMin: Double
    let xScale: CGFloat
    let yScale: CGFloat

    func point(_ x: Date, _ y: Double) -> CGPoint {
        return CGPoint(x: CGFloat(x.timeIntervalSince(startDate)) * xScale, y: CGFloat(y - glucoseMin) * yScale)
    }

    // By default enforce a minimum height so that the range is visible
    func rect(for range: WatchDatedRange, minHeight: CGFloat = 2) -> CGRect {
        let a = point(range.startDate, range.minValue)
        let b = point(range.endDate, range.maxValue)
        let size = CGSize(width: b.x - a.x, height: max(b.y - a.y, minHeight))
        return CGRect(origin: CGPoint(x: a.x + size.width / 2, y: a.y + size.height / 2), size: size)
    }
}

extension HKUnit {
    var highWatermarkRange: [Double] {
        if unitString == "mg/dL" {
            return [150.0, 200.0, 250.0, 300.0, 350.0, 400.0]
        } else {
            return [8.0, 11.0, 14.0, 17.0, 20.0, 23.0]
        }
    }

    var lowWatermark: Double {
        if unitString == "mg/dL" {
            return 50.0
        } else {
            return 3.0
        }
    }
}

extension WKInterfaceDevice {
    enum WatchSize {
        case watch38mm
        case watch40mm
        case watch42mm
        case watch44mm
    }

    func watchSize() -> WatchSize {
        switch screenBounds.width {
        case 136:
            return .watch38mm
        case 162:
            return .watch40mm
        case 184:
            return .watch44mm
        default:
            return .watch42mm
        }
    }
}

extension WatchDatedRange {
    var hashValue: UInt64 {
        var hashValue: Double
        hashValue = 2 * minValue
        hashValue += 3 * maxValue
        hashValue += 5 * startDate.timeIntervalSince1970
        hashValue += 7 * endDate.timeIntervalSince1970
        return UInt64(hashValue)
    }
}

extension SampleValue {
    var hashValue: UInt64 {
        var hashValue: Double
        hashValue = 2 * startDate.timeIntervalSince1970
        hashValue += 3 * quantity.doubleValue(for: HKUnit.milligramsPerDeciliter)
        return UInt64(hashValue)
    }
}


class GlucoseChartScene: SKScene {
    var unit: HKUnit?
    var temporaryOverride: WatchDatedRange?
    var historicalGlucose: [SampleValue]?
    var predictedGlucose: [SampleValue]?
    var targetRanges: [WatchDatedRange]?

    var visibleBg: Int = 1 {
        didSet {
            if let range = unit?.highWatermarkRange, (0..<range.count).contains(visibleBg) {
                WKInterfaceDevice.current().play(.success)
                maxBGLabel.setScale(2.0)
                maxBGLabel.run(SKAction.scale(to: 1.0, duration: 1.0), withKey: "highlight")
                updateNodes(animated: true)
            } else {
                visibleBg = oldValue
            }
        }
    }

    var visibleHours: Int = 3
    private var timer: Timer?
    private var hoursLabel: SKLabelNode!
    private var maxBGLabel: SKLabelNode!
    private var minBGLabel: SKLabelNode!
    private var nodes: [UInt64 : SKSpriteNode] = [:]
    private var predictedPathNode: SKShapeNode?

    override init() {
        // Use the fixed sizes specified in the storyboard, based on our guess of the model size
        super.init(size: {
            switch WKInterfaceDevice.current().watchSize() {
            case .watch38mm:
                return CGSize(width: 134, height: 90)
            case .watch40mm:
                return CGSize(width: 158, height: 100)
            case .watch42mm:
                return CGSize(width: 154, height: 100)
            case .watch44mm:
                return CGSize(width: 180, height: 115)
            }
        }())

        anchorPoint = CGPoint(x: 0, y: 0)
        scaleMode = .aspectFit
        backgroundColor = .backgroundColor

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

        // Force an update once a minute
        Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes: 1), repeats: true) { _ in
            self.updateNodes(animated: false)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func update(_ currentTime: TimeInterval) {
        if maxBGLabel.action(forKey: "highlight") == nil && predictedPathNode?.action(forKey: "move") == nil {
            DispatchQueue.main.async {
                self.isPaused = true
            }
        }
    }

    func getSprite(forHash hashValue: UInt64) -> SKSpriteNode {
        if nodes[hashValue] == nil {
            nodes[hashValue] = SKSpriteNode(color: .clear, size: CGSize(width: 0, height: 0))
            addChild(nodes[hashValue]!)
        }
        return nodes[hashValue]!
    }

    func updateNodes(animated: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let unit = unit else {
            return
        }

        let window = TimeInterval(hours: Double(visibleHours))
        let scaler = Scaler(startDate: Date() - window,
                            glucoseMin: unit.lowWatermark,
                            xScale: size.width / CGFloat(window * 2),
                            yScale: size.height / CGFloat(unit.highWatermarkRange[visibleBg] - unit.lowWatermark))


        let numberFormatter = NumberFormatter.glucoseFormatter(for: unit)
        minBGLabel.text = numberFormatter.string(from: unit.lowWatermark)
        maxBGLabel.text = numberFormatter.string(from: unit.highWatermarkRange[visibleBg])
        hoursLabel.text = "\(Int(visibleHours))h"

        // Keep track of the nodes we started this pass with so we can expire obsolete nodes at the end
        var inactiveNodes = nodes

        targetRanges?.forEach { range in
            let sprite = getSprite(forHash: range.hashValue)
            sprite.color = UIColor.rangeColor.withAlphaComponent(temporaryOverride != nil ? 0.4 : 0.6)
            sprite.move(to: scaler.rect(for: range), animated: animated)
            inactiveNodes.removeValue(forKey: range.hashValue)
        }

        // Make temporary overrides visually match what we do in the Loop app. This means that we have
        // one darker box which represents the duration of the override, but we have a second lighter box which
        // extends to the end of the visible window.
        if let range = temporaryOverride, range.endDate > Date() {
            let sprite1 = getSprite(forHash: range.hashValue)
            sprite1.color = UIColor.rangeColor.withAlphaComponent(0.6)
            sprite1.move(to: scaler.rect(for: range), animated: animated)
            inactiveNodes.removeValue(forKey: range.hashValue)

            let extendedRange = WatchDatedRange(startDate: range.startDate, endDate: Date() + window, minValue: range.minValue, maxValue: range.maxValue)
            let sprite2 = getSprite(forHash: extendedRange.hashValue)
            sprite2.color = UIColor.rangeColor.withAlphaComponent(0.4)
            sprite2.move(to: scaler.rect(for: extendedRange), animated: animated)
            inactiveNodes.removeValue(forKey: extendedRange.hashValue)
        }

        historicalGlucose?.filter { $0.startDate > scaler.startDate }.forEach {
            let origin = scaler.point($0.startDate, $0.quantity.doubleValue(for: unit))
            let pointSize = visibleHours < 3 ? 2.5 : 2
            let size = CGSize(width: pointSize, height: pointSize)
            let sprite = getSprite(forHash: $0.hashValue)
            sprite.color = .glucoseTintColor
            sprite.move(to: CGRect(origin: origin, size: size), animated: animated)
            inactiveNodes.removeValue(forKey: $0.hashValue)
        }

        predictedPathNode?.removeFromParent()
        if let predictedGlucose = predictedGlucose, predictedGlucose.count > 2 {
            let predictedPath = CGMutablePath()
            predictedPath.addLines(between: predictedGlucose.map {
                scaler.point($0.startDate, $0.quantity.doubleValue(for: unit))
            })

            predictedPathNode = SKShapeNode(path: predictedPath.copy(dashingWithPhase: 11, lengths: [5, 3]))
            addChild(predictedPathNode!)

            if animated {
                // SKShapeNode paths cannot be easily animated. Make it vanish, then fade in at the new location.
                predictedPathNode!.alpha = 0
                predictedPathNode!.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.25),
                    SKAction.fadeIn(withDuration: 0.75)
                    ]), withKey: "move")
            }
        }

        // Any inactive nodes can be safely removed
        inactiveNodes.forEach { hash, node in
            node.removeFromParent()
            nodes.removeValue(forKey: hash)
        }

        isPaused = false
    }
}
