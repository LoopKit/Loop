//
//  LoopStateView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

final class LoopStateView: UIView {
    enum Freshness {
        case Fresh
        case Aging
        case Stale
        case Unknown

        var color: UIColor {
            switch self {
            case .Fresh:
                return UIColor.freshColor
            case .Aging:
                return UIColor.agingColor
            case .Stale:
                return UIColor.staleColor
            case .Unknown:
                return UIColor.unknownColor
            }
        }
    }

    var freshness = Freshness.Unknown {
        didSet {
            shapeLayer.strokeColor = freshness.color.CGColor
        }
    }

    var open = false {
        didSet {
            if open != oldValue {
                shapeLayer.path = drawPath()
            }
        }
    }

    override class func layerClass() -> AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        shapeLayer.lineWidth = 8
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = freshness.color.CGColor

        shapeLayer.path = drawPath()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        shapeLayer.lineWidth = 8
        shapeLayer.fillColor = nil
        shapeLayer.strokeColor = freshness.color.CGColor

        shapeLayer.path = drawPath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        shapeLayer.path = drawPath()
    }

    private func drawPath(lineWidth lineWidth: CGFloat? = nil) -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let lineWidth = lineWidth ?? shapeLayer.lineWidth
        let radius = min(bounds.width / 2, bounds.height / 2) - lineWidth / 2

        let startAngle = open ? CGFloat(-M_PI_4) : 0
        let endAngle = open ? CGFloat(5 * M_PI_4) : CGFloat(2 * M_PI)

        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )

        return path.CGPath
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
                    group.duration = 1
                    group.repeatCount = HUGE
                    group.autoreverses = true
                    group.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)

                    shapeLayer.addAnimation(group, forKey: self.dynamicType.AnimationKey)
                } else {
                    shapeLayer.removeAnimationForKey(self.dynamicType.AnimationKey)
                }
            }
        }
    }
}

