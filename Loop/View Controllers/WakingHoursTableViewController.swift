//
//  WakingHoursTableViewController.swift
//  Loop
//
//  Created by Michael Pangburn on 9/25/18.
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import UIKit


final class WakingHoursTableViewController: DailyScheduleIntervalTableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Waking Hours", comment: "The title of the waking hours configuration screen")
    }

    // MARK: - UITableViewDataSource

    override func title(for row: Row) -> String {
        switch row {
        case .startTime:
            return NSLocalizedString("Wake Time", comment: "The title text for the Apple Watch wake time setting cell")
        case .endTime:
            return NSLocalizedString("Bed Time", comment: "The title text for the Apple Watch bed time setting cell")
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return NSLocalizedString("Loop uses your waking hours to better keep your Apple Watch complication up to date.", comment: "The footer text for the waking hours selection screen")
    }
}
