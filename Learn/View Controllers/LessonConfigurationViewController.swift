//
//  LessonConfigurationViewController.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKitUI

class LessonConfigurationViewController: UITableViewController {

    var lesson: Lesson!

    private enum State {
        case editing
        case executing
    }

    private var state = State.editing {
        didSet {
            guard state != oldValue else {
                return
            }

            if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: lesson.configurationSections.count)) as? TextButtonTableViewCell {
                cell.isLoading = state == .executing
                cell.isEnabled = state == .editing
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = lesson.title
        tableView.estimatedRowHeight = 44
        tableView.rowHeight = UITableView.automaticDimension

        for section in lesson.configurationSections {
            for cell in section.cells {
                cell.registerCell(for: self.tableView)
            }
        }

        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
    }

    /// If a tap occurs in the table view, but not on any cells, dismiss any active edits
    @IBAction private func dismissActiveEditing(gestureRecognizer: UITapGestureRecognizer) {
        let tapPoint = gestureRecognizer.location(in: tableView)
        guard tableView.indexPathForRow(at: tapPoint) == nil else {
            return
        }

        tableView.endEditing(false)
        tableView.beginUpdates()
        hideDatePickerCells()
        tableView.endUpdates()
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return lesson.configurationSections.count + 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == lesson.configurationSections.count {
            return 1
        } else {
            return lesson.configurationSections[section].cells.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == lesson.configurationSections.count {
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell
            cell.textLabel?.text = NSLocalizedString("Continue", comment: "Title of the button to begin lesson execution")

            switch state {
            case .editing:
                cell.isEnabled = true
                cell.isLoading = false
            case .executing:
                cell.isEnabled = false
                cell.isLoading = true
            }

            return cell
        } else {
            return lesson.configurationSections[indexPath.section].cells[indexPath.item].tableView(tableView, cellForRowAt: indexPath)
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section < lesson.configurationSections.count {
            return lesson.configurationSections[section].headerTitle
        } else {
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section < lesson.configurationSections.count {
            return lesson.configurationSections[section].footerTitle
        } else {
            return nil
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return state == .editing
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        guard case .editing = state else {
            return nil
        }

        tableView.endEditing(false)
        tableView.beginUpdates()
        hideDatePickerCells(excluding: indexPath)
        return indexPath
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.endUpdates()
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == lesson.configurationSections.count {
            state = .executing

            lesson.execute { resultSections in 
                dispatchPrecondition(condition: .onQueue(.main))

                self.performSegue(withIdentifier: LessonResultsViewController.className, sender: resultSections)

                self.state = .editing
            }
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        if let results = sender as? [LessonSectionProviding], let destination = segue.destination as? LessonResultsViewController {
            destination.lesson = lesson
            destination.results = results
        }
    }
}


extension LessonConfigurationViewController: DatePickerTableViewCellDelegate {
    func datePickerTableViewCellDidUpdateDate(_ cell: DatePickerTableViewCell) {

    }
}
