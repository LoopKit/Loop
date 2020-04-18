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
    let weeksEntry: NumberEntry
    let daysEntry: NumberEntry

    let cells: [LessonCellProviding]

    init(headerTitle: String? = nil, footerTitle: String? = nil, start: Date, weeks: Int, days: Int = 0) {
        self.headerTitle = headerTitle
        self.footerTitle = footerTitle

        self.dateEntry = DateEntry(date: start, title: NSLocalizedString("Start Date", comment: "Title of config entry"), mode: .date)
        self.weeksEntry = NumberEntry.integerEntry(value: weeks, unitString: NSLocalizedString("Weeks", comment: "Unit string for a count of calendar weeks"))
        self.daysEntry = NumberEntry.integerEntry(value: days, unitString: NSLocalizedString("Days", comment: "Unit string for a count of calendar days"))

        self.cells = [
            self.dateEntry,
            self.weeksEntry,
            self.daysEntry
        ]
    }
}

extension DateIntervalEntry {
    convenience init(headerTitle: String? = nil, footerTitle: String? = nil, end: Date, weeks: Int, days: Int = 0, calendar: Calendar = .current) {
        let start = calendar.date(byAdding: DateComponents(weekOfYear: -weeks), to: end)!
        self.init(headerTitle: headerTitle, footerTitle: footerTitle, start: calendar.startOfDay(for: start), weeks: weeks, days: days)
    }

    var dateInterval: DateInterval? {
        let start = dateEntry.date
        var end = dateEntry.date
        
        if let weeks = weeksEntry.number?.intValue,
           let endOfWeeks = Calendar.current.date(byAdding: DateComponents(weekOfYear: weeks), to: end)  {
            end = endOfWeeks;
        }
        if let days = daysEntry.number?.intValue,
           let endOfDays = Calendar.current.date(byAdding: DateComponents(day: days), to: end)  {
            end = endOfDays;
        }

        return DateInterval(start: start, end: end)
    }
}
