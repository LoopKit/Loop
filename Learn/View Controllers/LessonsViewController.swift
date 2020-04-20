//
//  LessonsViewController.swift
//  Learn
//
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit

class LessonsViewController: UITableViewController {
    
    var dataManager: DataManager!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let settingsButtons = UIBarButtonItem(title: "Settings", style: .done, target: self, action: #selector(settingsTapped(sender:)))
        self.navigationItem.rightBarButtonItem = settingsButtons
    }
    
    @objc func settingsTapped(sender: UIBarButtonItem) {
        self.performSegue(withIdentifier: "settings", sender: self)
    }


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
        
        let targetViewController = segue.destination

        switch targetViewController {
        case let vc as LessonConfigurationViewController:
            if let cell = sender as? UITableViewCell,
                let indexPath = tableView.indexPath(for: cell)
            {
                vc.lesson = lessons[indexPath.row]
            }
        case let vc as SettingsViewController:
            vc.dataSourceManager = dataManager.dataSourceManager
            vc.dataManager = dataManager
        default:
            break
        }
    }
}
