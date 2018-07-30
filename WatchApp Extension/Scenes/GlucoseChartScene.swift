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

struct Scaler {
    let startDate: Date
    let glucoseMin: Double
    let xScale: CGFloat
    let yScale: CGFloat

    func point(_ x: Date, _ y: Double) -> CGPoint {
        return CGPoint(x: CGFloat(x.timeIntervalSince(startDate)) * xScale, y: CGFloat(y - glucoseMin) * yScale)
    }

    func rect(for range: WatchDatedRange) -> CGRect {
        let a = point(range.startDate, range.minValue)
        let b = point(range.endDate, range.maxValue)
        let size = CGSize(width: b.x - a.x, height: b.y - a.y)
        return CGRect(origin: CGPoint(x: a.x + size.width / 2, y: a.y + size.height / 2), size: size)
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

extension WKInterfaceDevice {
    enum WatchSize {
        case Watch38mm
        case Watch42mm
    }

    func watchSize() -> WatchSize {
        switch screenBounds.width {
        case 136:
            return .Watch38mm
        default:
            return .Watch42mm
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

    private var visibleHours: Int = 3
    private var timer: Timer?
    private var hoursLabel: SKLabelNode!
    private var maxBGLabel: SKLabelNode!
    private var minBGLabel: SKLabelNode!
    private var nodes: [UInt64 : SKNode] = [:]
    private var predictedPathNode: SKShapeNode?

    override init() {
        // Use the fixed sizes specified in the storyboard, based on our guess of the model size
        super.init(size: {
            switch WKInterfaceDevice.current().watchSize() {
            case .Watch38mm:
                return CGSize(width: 134, height: 68)
            case .Watch42mm:
                return CGSize(width: 154, height: 86)
            }
        }())

        anchorPoint = CGPoint(x: 0, y: 0)
        scaleMode = .aspectFit
        backgroundColor = .clear

        let frame = SKShapeNode(rectOf: size, cornerRadius: 0)
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

    func updateSprite(for hashValue: UInt64, to color: UIColor, at rect: CGRect, animated: Bool) {
        if nodes[hashValue] as? SKSpriteNode == nil {
            nodes[hashValue] = SKSpriteNode(color: color, size: rect.size)
            nodes[hashValue]!.position = rect.origin
            addChild(nodes[hashValue]!)
        }

        let node = nodes[hashValue] as! SKSpriteNode
        node.color = color

        if animated {
            node.run(SKAction.group([
                SKAction.move(to: rect.origin, duration: 0.25),
                SKAction.resize(toWidth: rect.size.width, duration: 0.25),
                SKAction.resize(toHeight: rect.size.height, duration: 0.25)]))
        } else {
            node.size = rect.size
            node.position = rect.origin
        }
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

        var expire = nodes
        targetRanges?.forEach { range in
            updateSprite(for: range.hashValue,
                         to: UIColor.rangeColor.withAlphaComponent(temporaryOverride != nil ? 0.2 : 0.4),
                         at: scaler.rect(for: range),
                         animated: animated)
            expire.removeValue(forKey: range.hashValue)
        }

        if let range = temporaryOverride, range.endDate > Date() {
            let color = UIColor.rangeColor.withAlphaComponent(0.2)
            updateSprite(for: range.hashValue, to: color, at: scaler.rect(for: range), animated: animated)
            expire.removeValue(forKey: range.hashValue)

            let extendedRange = WatchDatedRange(startDate: range.startDate, endDate: Date() + window, minValue: range.minValue, maxValue: range.maxValue)
            updateSprite(for: extendedRange.hashValue, to: color, at: scaler.rect(for: extendedRange), animated: animated)
            expire.removeValue(forKey: extendedRange.hashValue)
        }

        historicalGlucose?.filter { $0.startDate > scaler.startDate }.forEach {
            let origin = scaler.point($0.startDate, $0.quantity.doubleValue(for: unit))
            let size = CGSize(width: 2, height: 2)
            updateSprite(for: $0.hashValue, to: .glucoseTintColor, at: CGRect(origin: origin, size: size), animated: animated)
            expire.removeValue(forKey: $0.hashValue)
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
                predictedPathNode!.alpha = 0
                predictedPathNode!.run(SKAction.sequence([
                    SKAction.wait(forDuration: 0.25),
                    SKAction.fadeIn(withDuration: 0.75)
                    ]), withKey: "move")
            }
        }
        expire.forEach { hash, node in
            node.removeFromParent()
            nodes.removeValue(forKey: hash)
        }

        isPaused = false
    }
}
