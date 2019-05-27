//
//  ButtonGroup.swift
//  WatchApp Extension
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import WatchKit


class ButtonGroup {
    private let button: WKInterfaceButton
    private let image: WKInterfaceImage
    private let background: WKInterfaceGroup
    private let onBackgroundColor: UIColor
    private let offBackgroundColor: UIColor

    enum State {
        case on
        case off
        case disabled
    }

    var state: State = .off {
        didSet {
            let imageTintColor: UIColor
            let backgroundColor: UIColor
            switch state {
            case .on:
                imageTintColor = offBackgroundColor
                backgroundColor = onBackgroundColor
            case .off:
                imageTintColor = onBackgroundColor
                backgroundColor = offBackgroundColor
            case .disabled:
                imageTintColor = .disabledButtonColor
                backgroundColor = .darkDisabledButtonColor
            }

            button.setEnabled(state != .disabled)
            image.setTintColor(imageTintColor)
            background.setBackgroundColor(backgroundColor)
        }
    }

    init(button: WKInterfaceButton, image: WKInterfaceImage, background: WKInterfaceGroup, onBackgroundColor: UIColor, offBackgroundColor: UIColor) {
        self.button = button
        self.image = image
        self.background = background
        self.onBackgroundColor = onBackgroundColor
        self.offBackgroundColor = offBackgroundColor
    }

    func turnOff() {
        switch state {
        case .on:
            state = .off
        case .off, .disabled:
            break
        }
    }
}
