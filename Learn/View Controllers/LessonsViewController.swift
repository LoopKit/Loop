//
//  LessonsViewController.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit

class LessonsViewController: UITableViewController {

    var lessons: [Lesson] = [] {
        didSet {
            if isViewLoaded {
                tableView.reloadData()
            }
        }
    }

    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return lessons.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Lesson", for: indexPath)
        let lesson = lessons[indexPath.row]

        cell.textLabel?.text = lesson.title
        cell.detailTextLabel?.text = lesson.subtitle

        return cell
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        if let configVC = segue.destination as? LessonConfigurationViewController,
            let cell = sender as? UITableViewCell,
            let indexPath = tableView.indexPath(for: cell)
        {
            configVC.lesson = lessons[indexPath.row]
        }
    }
}
