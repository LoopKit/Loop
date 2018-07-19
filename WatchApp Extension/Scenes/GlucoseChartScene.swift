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
}

extension SampleValue {
    var hashValue: Double {
        return 17 * quantity.doubleValue(for: HKUnit.milligramsPerDeciliter) +
            23 * startDate.timeIntervalSince1970
    }
}

extension SKLabelNode {
    static func basic() -> SKLabelNode {
        let basic = SKLabelNode(text: "--")
        basic.fontSize = 12
        basic.fontName = "HelveticaNeue"
        basic.fontColor = .white
        basic.alpha = 0.8
        basic.verticalAlignmentMode = .top
        basic.horizontalAlignmentMode = .left
        return basic
    }
}

class GlucoseChartScene: SKScene {
    var unit: HKUnit?
    var targetRanges: [WatchDatedRange]?
    var temporaryOverride: WatchDatedRange?
    var historicalGlucose: [SampleValue]?
    var predictedGlucose: [SampleValue]?
    var visibleHours: Int = 2 {
        didSet {
            if visibleHours > 6 {
                visibleHours = 6
            } else if visibleHours < 2 {
                visibleHours = 2
            } else {
                WKInterfaceDevice.current().play(.success)
                nextUpdate = Date()
            }
        }
    }

    private var nextUpdate = Date()
    private var hoursLabel: SKLabelNode!
    private var sampleNodes: [Double: SKShapeNode] = [:]

    override init() {
        // Use the fixed sizes specified in the storyboard, based on our guess of the model size
        var sceneSize: CGSize
        if WKInterfaceDevice.current().screenBounds.width > 136 {
            sceneSize = CGSize(width: 154, height: 110)
        } else {
            sceneSize = CGSize(width: 134, height: 110)
        }
        super.init(size: sceneSize)

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

        hoursLabel = SKLabelNode.basic()
        hoursLabel.position = CGPoint(x: 5, y: size.height - 5)
        addChild(hoursLabel)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func update(_ currentTime: TimeInterval) {
        guard let unit = unit, Date() >= nextUpdate else {
            return
        }

        let window = TimeInterval(hours: Double(visibleHours))
        let start = Date() - (window / 2)
        let xScale = size.width / CGFloat(window)
        let yScale = size.height / CGFloat(200 - 50)

        hoursLabel.text = "\(Int(visibleHours))h"

        var expiredNodes = sampleNodes
        historicalGlucose?.filter { $0.startDate > start }.forEach {
            let hashValue = $0.hashValue
            if sampleNodes[hashValue] == nil {
                let node = SKShapeNode(circleOfRadius: 1)
                node.fillColor = .glucoseTintColor
                node.strokeColor = .clear
                node.position = position
                sampleNodes[$0.hashValue] = node
                addChild(node)
            }

            sampleNodes[hashValue]!.position =
                CGPoint(x: CGFloat($0.startDate.timeIntervalSince(start)) * xScale,
                        y: CGFloat($0.quantity.doubleValue(for: unit) - 50) * yScale)
            expiredNodes.removeValue(forKey: hashValue)
        }

        expiredNodes.forEach {
            sampleNodes.removeValue(forKey: $0.key)
            $0.value.removeFromParent()
        }

        nextUpdate = Date() + TimeInterval(minutes: 1)
    }
}
