//
//  CarbDateInterfaceController.swift
//  WatchApp Extension
//
//  Created by Michael Pangburn on 10/10/17.
//  Copyright © 2017 LoopKit Authors. All rights reserved.
//

import WatchKit
import Foundation


protocol CarbDateInterfaceControllerDelegate: class {
    var date: Date { get set }
    func didConfirmDate(_ date: Date)
}

class CarbDateInterfaceController: WKInterfaceController, IdentifiableClass {

    weak var delegate: CarbDateInterfaceControllerDelegate?

    private var date = Date() {
        didSet {
            dateLabel.setText(dateFormatter.string(from: date))
            timeLabel.setText(timeFormatter.string(from: date))
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yy"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    @IBOutlet var dateLabel: WKInterfaceLabel!
    @IBOutlet var timeLabel: WKInterfaceLabel!

    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        crownSequencer.delegate = self
        guard let delegate = context as? CarbDateInterfaceControllerDelegate else {
            return
        }
        self.delegate = delegate
        date = delegate.date
    }

    override func willActivate() {
        super.willActivate()
        crownSequencer.focus()
    }

    @IBAction func incrementDate() {
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: date) else {
            return
        }
        date = nextDay
    }

    @IBAction func decrementDate() {
        guard let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: date) else {
            return
        }
        date = previousDay
    }

    @IBAction func incrementTime() {
        guard let fiveMinutesLater = Calendar.current.date(byAdding: .minute, value: 5, to: date) else {
            return
        }
        date = fiveMinutesLater
    }

    @IBAction func decrementTime() {
        guard let fiveMinutesEarlier = Calendar.current.date(byAdding: .minute, value: -5, to: date) else {
            return
        }
        date = fiveMinutesEarlier
    }

    @IBAction func save() {
        delegate?.didConfirmDate(date)
        dismiss()
    }

    // MARK: - Crown Sequencer

    private var accumulatedRotation: Double = 0
}

private let rotationsPerMinute: Double = 1/24

extension CarbDateInterfaceController: WKCrownDelegate {
    func crownDidRotate(_ crownSequencer: WKCrownSequencer?, rotationalDelta: Double) {
        accumulatedRotation += rotationalDelta

        let remainder = accumulatedRotation.truncatingRemainder(dividingBy: rotationsPerMinute)
        let minutes = Int((accumulatedRotation - remainder) / rotationsPerMinute)
        accumulatedRotation = remainder
        guard let changedDate = Calendar.current.date(byAdding: .minute, value: minutes, to: date) else {
            return
        }
        date = changedDate
    }
}
