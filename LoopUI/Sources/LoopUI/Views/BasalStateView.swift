//
//  BasalStateView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit


public final class BasalStateView: UIView {

    var netBasalPercent: Double = 0 {
        didSet {
            animateToPath(drawPath())
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

        shapeLayer.lineWidth = 2
        updateTintColor()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        shapeLayer.lineWidth = 2
        updateTintColor()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
    }

    public override func tintColorDidChange() {
        super.tintColorDidChange()
        updateTintColor()
    }

    private func updateTintColor() {
        shapeLayer.fillColor = tintColor.withAlphaComponent(0.5).cgColor
        shapeLayer.strokeColor = tintColor.cgColor
    }

    private func drawPath() -> CGPath {
        let startX = bounds.minX
        let endX = bounds.maxX
        let midY = bounds.midY

        let path = UIBezierPath()
        path.move(to: CGPoint(x: startX, y: midY))

        let leftAnchor = startX + 1/6 * bounds.size.width
        let rightAnchor = startX + 5/6 * bounds.size.width

        let yAnchor = bounds.midY - CGFloat(netBasalPercent) * (bounds.size.height - shapeLayer.lineWidth) / 2

        path.addLine(to: CGPoint(x: leftAnchor, y: midY))
        path.addLine(to: CGPoint(x: leftAnchor, y: yAnchor))
        path.addLine(to: CGPoint(x: rightAnchor, y: yAnchor))
        path.addLine(to: CGPoint(x: rightAnchor, y: midY))
        path.addLine(to: CGPoint(x: endX, y: midY))

        return path.cgPath
    }

    private static let AnimationKey = "com.loudnate.Naterade.shapePathAnimation"

    private func animateToPath(_ path: CGPath) {
        if shapeLayer.path != nil {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = shapeLayer.path ?? drawPath()
            animation.toValue = path
            animation.duration = 1
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            shapeLayer.add(animation, forKey: type(of: self).AnimationKey)
        }

        shapeLayer.path = path
    }
}
