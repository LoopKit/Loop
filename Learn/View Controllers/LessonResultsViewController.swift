//
//  LessonResultsViewController.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import LoopCore
import UIKit


class LessonResultsViewController: UITableViewController, IdentifiableClass {

    var lesson: Lesson!

    var results: [LessonSectionProviding] = [] {
        didSet {
            if isViewLoaded {
                tableView.reloadData()
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = lesson.title

        for section in results {
            for cell in section.cells {
                cell.registerCell(for: self.tableView)
            }
        }
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return results.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results[section].cells.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return results[indexPath.section].cells[indexPath.row].tableView(tableView, cellForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        return nil
    }

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return false
    }

}
