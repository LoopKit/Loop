//
//  LevelMaskView.swift
//  Loop
//
//  Created by Nate Racklyeft on 8/28/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import UIKit

// Displays a variable-height level indicator, masked by an image.
// Inspired by https://github.com/carekit-apple/CareKit/blob/master/CareKit/CareCard/OCKHeartView.h

class LevelMaskView: UIView {

    var value: Double = 1.0 {
        didSet {
            animateFill()
        }
    }

    @IBInspectable var maskImage: UIImage? {
        didSet {
            fillView?.removeFromSuperview()
            maskView?.removeFromSuperview()
            maskImageView?.removeFromSuperview()

            guard let maskImage = maskImage else { return }

            maskView = UIView()
            maskImageView = UIImageView(image: maskImage)
            maskImageView!.contentMode = .Center
            maskView!.addSubview(maskImageView!)

            clipsToBounds = true

            fillView = UIView()
            fillView!.backgroundColor = tintColor
            addSubview(fillView!)
        }
    }

    private var fillView: UIView?

    private var maskImageView: UIView?

    override func layoutSubviews() {
        super.layoutSubviews()

        guard let maskImage = maskImage else { return }

        let maskImageSize = maskImage.size

        maskView?.frame = CGRect(origin: .zero, size: maskImageSize)
        maskView?.center = CGPoint(x: bounds.midX, y: bounds.midY)
        maskImageView?.frame = maskView?.bounds ?? bounds

        if (fillView?.layer.animationKeys()?.count ?? 0) == 0 {
            updateFillViewFrame()
        }
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        fillView?.backgroundColor = tintColor
    }

    private func animateFill() {
        UIView.animateWithDuration(1.25, delay: 0, options: .BeginFromCurrentState, animations: {
            self.updateFillViewFrame()
        }, completion: nil)
    }

    private func updateFillViewFrame() {
        guard let maskViewFrame = maskView?.frame else { return }

        var fillViewFrame = maskViewFrame
        fillViewFrame.origin.y = maskViewFrame.maxY
        fillViewFrame.size.height = -CGFloat(value) * maskViewFrame.height
        fillView?.frame = fillViewFrame
    }
}
