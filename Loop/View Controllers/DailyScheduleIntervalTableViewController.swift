//
//  DailyScheduleIntervalTableViewController.swift
//  Loop
//
//  Created by Michael Pangburn on 9/24/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit


protocol DailyScheduleIntervalTableViewControllerDelegate: AnyObject {
    func dailyScheduleIntervalTableViewController(_ controller: DailyScheduleIntervalTableViewController, dailyScheduleIntervalDidChangeTo dailyScheduleInterval: DailyScheduleInterval)
}

class DailyScheduleIntervalTableViewController: UITableViewController {
    var dailyScheduleInterval: DailyScheduleInterval

    weak var delegate: DailyScheduleIntervalTableViewControllerDelegate?

    init(dailyScheduleInterval: DailyScheduleInterval) {
        self.dailyScheduleInterval = dailyScheduleInterval
        super.init(style: .grouped)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(DateAndDurationTableViewCell.nib(), forCellReuseIdentifier: DateAndDurationTableViewCell.className)
    }

    // MARK: - UITableViewDataSource

    enum Row: Int, CaseIterable {
        case startTime
        case endTime
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DateAndDurationTableViewCell.className, for: indexPath) as! DateAndDurationTableViewCell
        cell.datePicker.datePickerMode = .time
        let row = Row(rawValue: indexPath.row)!
        cell.titleLabel.text = title(for: row)
        cell.date = {
            let dayInsensitiveDates = dailyScheduleInterval.dayInsensitiveDates()
            switch row {
            case .startTime:
                return dayInsensitiveDates.start
            case .endTime:
                return dayInsensitiveDates.end
            }
        }()
        cell.delegate = self

        return cell
    }

    func title(for row: Row) -> String {
        switch row {
        case .startTime:
            return NSLocalizedString("Start Time", comment: "The title text for the daily schedule interval picker start time cell")
        case .endTime:
            return NSLocalizedString("End Time", comment: "The title text for the daily schedule interval picker end time cell")
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        tableView.endEditing(false)
        tableView.beginUpdates()
        hideDatePickerCells(excluding: indexPath)
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.endUpdates()
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

extension DailyScheduleIntervalTableViewController: DatePickerTableViewCellDelegate {
    func datePickerTableViewCellDidUpdateDate(_ cell: DatePickerTableViewCell) {
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        switch Row(rawValue: indexPath.row)! {
        case .startTime:
            dailyScheduleInterval.startTime = DailyScheduleTime(of: cell.date)
        case .endTime:
            dailyScheduleInterval.endTime = DailyScheduleTime(of: cell.date)
        }

        delegate?.dailyScheduleIntervalTableViewController(self, dailyScheduleIntervalDidChangeTo: dailyScheduleInterval)
    }
}
