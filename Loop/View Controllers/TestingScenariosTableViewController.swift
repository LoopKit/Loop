//
//  TestingScenariosTableViewController.swift
//  Loop
//
//  Created by Michael Pangburn on 4/20/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKitUI


final class TestingScenariosTableViewController: RadioSelectionTableViewController {

    private let scenariosManager: TestingScenariosManager

    private var scenarioURLs: [URL] = [] {
        didSet {
            options = scenarioURLs.map { $0.deletingPathExtension().lastPathComponent }
            if isViewLoaded {
                DispatchQueue.main.async {
                    self.updateLoadButtonEnabled()
                    self.tableView.reloadData()
                }
            }
        }
    }

    override var selectedIndex: Int? {
        didSet {
            updateLoadButtonEnabled()
        }
    }

    private lazy var loadButtonItem = UIBarButtonItem(title: "Load", style: .done, target: self, action: #selector(loadSelectedScenario))

    init(scenariosManager: TestingScenariosManager) {
        assertDebugOnly()

        self.scenariosManager = scenariosManager
        super.init(style: .grouped)
        scenariosManager.delegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.navigationBar.prefersLargeTitles = true
        title = "🧪 Scenarios"
        navigationItem.rightBarButtonItem = loadButtonItem
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        contextHelp = "The scenarios directory location is available in the debug output of the Xcode console."

        if let activeScenarioURL = scenariosManager.activeScenarioURL {
            selectedIndex = scenarioURLs.firstIndex(of: activeScenarioURL)
        }

        updateLoadButtonEnabled()
    }

    override func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let url = scenarioURLs[indexPath.row]

        let rewindScenario = contextualAction(
            rowTitle: "⏮ Rewind",
            alertTitle: "Rewind Scenario",
            message: "Step backward a number of loop iterations.",
            loadScenario: { self.scenariosManager.loadScenario(from: url, rewoundByLoopIterations: $0, completion: $1) }
        )
        rewindScenario.backgroundColor = .lightGray

        return UISwipeActionsConfiguration(actions: [rewindScenario])
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let url = scenarioURLs[indexPath.row]

        let advanceScenario = contextualAction(
            rowTitle: "Advance ⏭",
            alertTitle: "Advance Scenario",
            message: "Step forward a number of loop iterations.",
            loadScenario: { self.scenariosManager.loadScenario(from: url, advancedByLoopIterations: $0, completion: $1) }
        )
        advanceScenario.backgroundColor = .HIGGreenColor()

        return UISwipeActionsConfiguration(actions: [advanceScenario])
    }

    private func contextualAction(
        rowTitle: String, alertTitle: String, message: String,
        loadScenario: @escaping (_ iterations: Int, _ completion: @escaping (Error?) -> Void) -> Void
    ) -> UIContextualAction {
        return UIContextualAction(style: .normal, title: rowTitle) { action, sourceView, completion in
            let alert = UIAlertController(
                title: alertTitle,
                message: message,
                cancelButtonTitle: "Cancel",
                okButtonTitle: "OK",
                validate: { text in
                    guard let iterations = Int(text) else {
                        return false
                    }
                    return iterations > 0
                },
                textFieldConfiguration: { textField in
                    textField.placeholder = "Iteration count"
                    textField.keyboardType = .numberPad
                }
            ) { result in
                switch result {
                case .cancel:
                    completion(false)
                case .ok(let iterationsText):
                    let iterations = Int(iterationsText)!
                    loadScenario(iterations) { [weak self] _ in
                        self?.dismiss(animated: true)
                    }
                    completion(true)
                }
            }

            self.present(alert, animated: true)
        }
    }

    private func updateLoadButtonEnabled() {
        loadButtonItem.isEnabled = !scenarioURLs.isEmpty && selectedIndex != nil
    }

    @objc private func loadSelectedScenario() {
        guard let selectedIndex = selectedIndex else {
            assertionFailure("Loading should be possible only when a scenario is selected")
            return
        }

        let url = scenarioURLs[selectedIndex]
        scenariosManager.loadScenario(from: url) { error in
            DispatchQueue.main.async {
                if let error = error {
                    self.present(UIAlertController(with: error), animated: true)
                } else {
                    self.dismiss(animated: true)
                }
            }
        }
    }

    @objc private func cancel() {
        self.dismiss(animated: true)
    }
}

extension TestingScenariosTableViewController: TestingScenariosManagerDelegate {
    func testingScenariosManager(_ manager: TestingScenariosManager, didUpdateScenarioURLs scenarioURLs: [URL]) {
        self.scenarioURLs = scenarioURLs
    }
}
