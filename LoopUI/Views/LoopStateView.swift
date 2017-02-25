//
//  LoopStateView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/7/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

public final class LoopStateView: UIView {
    var firstDataUpdate = true
    
    enum Freshness {
        case fresh
        case aging
        case stale
        case unknown

        var color: UIColor {
            switch self {
            case .fresh:
                return UIColor.freshColor
            case .aging:
                return UIColor.agingColor
            case .stale:
                return UIColor.staleColor
            case .unknown:
                return UIColor.unknownColor
            }
        }
    }

    var freshness = Freshness.unknown {
        didSet {
            shapeLayer.strokeColor = freshness.color.cgColor
        }
    }

    var open = false {
        didSet {
            if open != oldValue {
                shapeLayer.path = drawPath()
            }
        }
    }

    override public class var layerClass : AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        shapeLayer.lineWidth = 8
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = freshness.color.cgColor

        shapeLayer.path = drawPath()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        shapeLayer.lineWidth = 8
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = freshness.color.cgColor

        shapeLayer.path = drawPath()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        shapeLayer.path = drawPath()
    }

    private func drawPath(lineWidth: CGFloat? = nil) -> CGPath {
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
                    group.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)

                    shapeLayer.add(group, forKey: type(of: self).AnimationKey)
                } else {
                    shapeLayer.removeAnimation(forKey: type(of: self).AnimationKey)
                }
            }
            firstDataUpdate = false
        }
    }
}

