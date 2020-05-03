//
//  SettingsViewController.swift
//  Learn
//
//  Created by Pete Schwamb on 4/19/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import UIKit
import LoopKitUI
import LoopUI
import LoopKit

class SettingsViewController: UITableViewController {
    
    var dataSourceManager: DataSourceManager!
    
    // MARK: - Table view data source
    enum Section: Int, CaseIterable {
        case dataSources
        case actions
    }
    
    enum Action: Int, CaseIterable {
        case addDataSource
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .dataSources:
            return NSLocalizedString("Data Sources", comment: "Section header for data sources list in settings")
        case .actions:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .dataSources:
            return dataSourceManager.dataSources.count
        case .actions:
            return Action.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .dataSources:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath)
            let dataSource = dataSourceManager.dataSources[indexPath.row]
            cell.textLabel?.text = dataSource.category
            cell.detailTextLabel?.text = dataSource.title
            cell.accessoryType = dataSource.identifier == dataSourceManager.selectedDataSource?.identifier ? .checkmark : .none
            return cell
        case .actions:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath)
            let action = Action(rawValue: indexPath.row)!
            switch action {
            case .addDataSource:
                cell.textLabel?.text = NSLocalizedString("Add Data Source", comment: "Title text for button to set up a new pump")
            }
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sender = tableView.cellForRow(at: indexPath)
        
        switch Section(rawValue: indexPath.section)! {
        case .dataSources:
            let dataSource = dataSourceManager.dataSources[indexPath.row]
            self.dataSourceManager.selectedDataSource = dataSource
            self.tableView.reloadSections([Section.dataSources.rawValue], with: .automatic)
            break
        case .actions:
            let action = Action(rawValue: indexPath.row)!
            switch action {
            case .addDataSource:
                let service = NightscoutService(siteURL: nil, APISecret: nil)
                let vc = AuthenticationViewController(authentication: service)
                vc.authenticationObserver = { [weak self] (service) in
                    if let url = service.siteURL, let host = url.host, let api = service.uploader, let secret = service.APISecret, let self = self {
                        let source = NightscoutDataSource(title: host, identifier: host, api: api)
                        let keychain = KeychainManager()
                        keychain.storeNightscoutCredentials(identifier: host, url: url, secret: secret)
                        self.dataSourceManager.addNightscoutDataSource(source)

                        self.tableView.reloadSections([Section.dataSources.rawValue], with: .automatic)
                    }
                }

                show(vc, sender: sender)

            }
        }
    }
}
