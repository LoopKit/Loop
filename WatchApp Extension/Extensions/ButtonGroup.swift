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
    private let onIconColor: UIColor
    private let offIconColor: UIColor

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
                imageTintColor = onIconColor
                backgroundColor = onBackgroundColor
            case .off:
                imageTintColor = offIconColor
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

    init(button: WKInterfaceButton,
         image: WKInterfaceImage,
         background: WKInterfaceGroup,
         onBackgroundColor: UIColor,
         offBackgroundColor: UIColor,
         onIconColor: UIColor,
         offIconColor: UIColor)
    {
        self.button = button
        self.image = image
        self.background = background
        self.onBackgroundColor = onBackgroundColor
        self.offBackgroundColor = offBackgroundColor
        self.onIconColor = onIconColor
        self.offIconColor = offIconColor
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
