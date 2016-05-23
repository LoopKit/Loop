//
//  BasalStateView.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/12/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

class BasalStateView: UIView {
    var netBasalPercent: Double = 0 {
        didSet {
            animateToPath(drawPath())
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

        shapeLayer.lineWidth = 2
        shapeLayer.fillColor = UIColor.doseTintColor.colorWithAlphaComponent(0.5).CGColor
        shapeLayer.strokeColor = UIColor.doseTintColor.CGColor

        shapeLayer.path = drawPath()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        shapeLayer.lineWidth = 2
        shapeLayer.fillColor = UIColor.doseTintColor.colorWithAlphaComponent(0.5).CGColor
        shapeLayer.strokeColor = UIColor.doseTintColor.CGColor

        shapeLayer.path = drawPath()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        shapeLayer.path = drawPath()
    }

    private func drawPath() -> CGPath {
        let startX = bounds.minX
        let endX = bounds.maxX
        let midY = bounds.midY

        let path = UIBezierPath()
        path.moveToPoint(CGPoint(x: startX, y: midY))

        let leftAnchor = startX + 1/6 * bounds.size.width
        let rightAnchor = startX + 5/6 * bounds.size.width

        let yAnchor = bounds.midY - CGFloat(netBasalPercent) * (bounds.size.height - shapeLayer.lineWidth) / 2

        path.addLineToPoint(CGPoint(x: leftAnchor, y: midY))
        path.addLineToPoint(CGPoint(x: leftAnchor, y: yAnchor))
        path.addLineToPoint(CGPoint(x: rightAnchor, y: yAnchor))
        path.addLineToPoint(CGPoint(x: rightAnchor, y: midY))
        path.addLineToPoint(CGPoint(x: endX, y: midY))

        return path.CGPath
    }

    private static let AnimationKey = "com.loudnate.Naterade.shapePathAnimation"

    private func animateToPath(path: CGPath) {
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = shapeLayer.path ?? drawPath()
        animation.toValue = path
        animation.duration = 1
        animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)

        shapeLayer.addAnimation(animation, forKey: self.dynamicType.AnimationKey)
        
        shapeLayer.path = path
    }
}
