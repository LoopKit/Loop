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

public class LevelMaskView: UIView {
    var firstDataUpdate = true

    var value: Double = 1.0 {
        didSet {
            animateFill(duration: firstDataUpdate ? 0 : 1.25)
            firstDataUpdate = false
        }
    }

    @IBInspectable var maskImage: UIImage? {
        didSet {
            fillView?.removeFromSuperview()
            mask?.removeFromSuperview()
            maskImageView?.removeFromSuperview()

            guard let maskImage = maskImage else { return }

            mask = UIView()
            maskImageView = UIImageView(image: maskImage)
            maskImageView!.contentMode = .center
            mask!.addSubview(maskImageView!)

            clipsToBounds = true

            fillView = UIView()
            fillView!.backgroundColor = tintColor
            addSubview(fillView!)
        }
    }

    private var fillView: UIView?

    private var maskImageView: UIView?

    override public func layoutSubviews() {
        super.layoutSubviews()

        guard let maskImage = maskImage else { return }

        let maskImageSize = maskImage.size

        mask?.frame = CGRect(origin: .zero, size: maskImageSize)
        mask?.center = CGPoint(x: bounds.midX, y: bounds.midY)
        maskImageView?.frame = mask?.bounds ?? bounds

        if (fillView?.layer.animationKeys()?.count ?? 0) == 0 {
            updateFillViewFrame()
        }
    }

    override public func tintColorDidChange() {
        super.tintColorDidChange()

        fillView?.backgroundColor = tintColor
    }

    private func animateFill(duration: TimeInterval) {
        UIView.animate(withDuration: duration, delay: 0, options: .beginFromCurrentState, animations: {
            self.updateFillViewFrame()
        }, completion: nil)
    }

    private func updateFillViewFrame() {
        guard let maskViewFrame = mask?.frame else { return }

        var fillViewFrame = maskViewFrame
        fillViewFrame.origin.y = maskViewFrame.maxY
        fillViewFrame.size.height = -CGFloat(value) * maskViewFrame.height
        fillView?.frame = fillViewFrame
    }
}
