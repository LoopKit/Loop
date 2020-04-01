//
//  DosingStrategySelectionViewController.swift
//  Loop
//
//  Created by Pete Schwamb on 12/27/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit
import HealthKit
import LoopCore
import LoopKit
import LoopUI


protocol DosingStrategySelectionViewControllerDelegate: class {
    func dosingStrategySelectionViewControllerDidChangeValue(_ controller: DosingStrategySelectionViewController)
}


class DosingStrategySelectionViewController: UITableViewController, IdentifiableClass {

    /// The currently-selected strategy.
    var dosingStrategy: DosingStrategy?

    var initialDosingStrategy: DosingStrategy?
    
    weak var delegate: DosingStrategySelectionViewControllerDelegate?

    // MARK: - UIViewController

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 91
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Record the configured dosingStrategy for change tracking
        initialDosingStrategy = dosingStrategy
    }

    override func viewWillDisappear(_ animated: Bool) {
        // Notify observers if the strategy changed since viewDidAppear
        if dosingStrategy != initialDosingStrategy {
            delegate?.dosingStrategySelectionViewControllerDidChangeValue(self)
        }

        super.viewWillDisappear(animated)
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return DosingStrategy.allCases.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let strategy = DosingStrategy(rawValue: indexPath.row)!
        let cell = tableView.dequeueReusableCell(withIdentifier: TitleSubtitleTextFieldTableViewCell.className, for: indexPath) as! TitleSubtitleTextFieldTableViewCell
        let isSelected = strategy == dosingStrategy
        cell.tintColor = isSelected ? nil : .clear
        cell.titleLabel.text = strategy.title
        cell.subtitleLabel.text = strategy.subtitle
        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        let selectedStrategy = DosingStrategy(rawValue: indexPath.row)!
        dosingStrategy = selectedStrategy

        for strategy in DosingStrategy.allCases {
            guard let cell = tableView.cellForRow(at: IndexPath(row: strategy.rawValue, section: 0)) as? TitleSubtitleTextFieldTableViewCell else {
                continue
            }

            let isSelected = dosingStrategy == strategy
            cell.tintColor = isSelected ? nil : .clear
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }
}
