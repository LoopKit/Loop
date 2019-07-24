//
//  LoopStateView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

final class LoopStateView: UIView {
    var firstDataUpdate = true
    
    override func tintColorDidChange() {
        super.tintColorDidChange()

        updateTintColor()
    }

    private func updateTintColor() {
        shapeLayer.strokeColor = tintColor.cgColor
    }

    var open = false {
        didSet {
            if open != oldValue {
                shapeLayer.path = drawPath()
            }
        }
    }

    override class var layerClass : AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        shapeLayer.lineWidth = 8
        shapeLayer.fillColor = UIColor.clear.cgColor
        updateTintColor()

        shapeLayer.path = drawPath()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        shapeLayer.lineWidth = 8
        shapeLayer.fillColor = UIColor.clear.cgColor
        updateTintColor()

        shapeLayer.path = drawPath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        shapeLayer.path = drawPath()
    }

    private func drawPath(lineWidth: CGFloat? = nil) -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let lineWidth = lineWidth ?? shapeLayer.lineWidth
        let radius = min(bounds.width / 2, bounds.height / 2) - lineWidth / 2

        let startAngle = open ? -CGFloat.pi / 4 : 0
        let endAngle = open ? 5 * CGFloat.pi / 4 : 2 * CGFloat.pi

        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )

        return path.cgPath
    }

    private static let AnimationKey = "com.loudnate.Naterade.breatheAnimation"

    var animated: Bool = false {
        didSet {
            if animated != oldValue {
                if animated {
                    let path = CABasicAnimation(keyPath: "path")
                    path.fromValue = shapeLayer.path ?? drawPath()
                    path.toValue = drawPath(lineWidth: 16)

                    let width = CABasicAnimation(keyPath: "lineWidth")
                    width.fromValue = shapeLayer.lineWidth
                    width.toValue = 10

                    let group = CAAnimationGroup()
                    group.animations = [path, width]
                    group.duration = firstDataUpdate ? 0 : 1
                    group.repeatCount = HUGE
                    group.autoreverses = true
                    group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

                    shapeLayer.add(group, forKey: type(of: self).AnimationKey)
                } else {
                    shapeLayer.removeAnimation(forKey: type(of: self).AnimationKey)
                }
            }
            firstDataUpdate = false
        }
    }
}

