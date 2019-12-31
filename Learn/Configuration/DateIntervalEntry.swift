//
//  DateIntervalEntry.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit


class DateIntervalEntry: LessonSectionProviding {
    let headerTitle: String?

    let footerTitle: String?

    let dateEntry: DateEntry
    let numberEntry: NumberEntry

    let cells: [LessonCellProviding]

    init(headerTitle: String? = nil, footerTitle: String? = nil, start: Date, weeks: Int) {
        self.headerTitle = headerTitle
        self.footerTitle = footerTitle

        self.dateEntry = DateEntry(date: start, title: NSLocalizedString("Start Date", comment: "Title of config entry"), mode: .date)
        self.numberEntry = NumberEntry.integerEntry(value: weeks, unitString: NSLocalizedString("Weeks", comment: "Unit string for a count of calendar weeks"))

        self.cells = [
            self.dateEntry,
            self.numberEntry
        ]
    }
}

extension DateIntervalEntry {
    convenience init(headerTitle: String? = nil, footerTitle: String? = nil, end: Date, weeks: Int, calendar: Calendar = .current) {
        let start = calendar.date(byAdding: DateComponents(weekOfYear: -weeks), to: end)!
        self.init(headerTitle: headerTitle, footerTitle: footerTitle, start: calendar.startOfDay(for: start), weeks: weeks)
    }

    var dateInterval: DateInterval? {
        let start = dateEntry.date

        guard let weeks = numberEntry.number?.intValue,
            let end = Calendar.current.date(byAdding: DateComponents(weekOfYear: weeks), to: start)
        else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }
}
