//
//  OTPSelectionViewController.swift
//  Loop
//
//  Created by Jose Paredes on 3/26/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import UIKit
import HealthKit
import Intents
import LoopCore
import LoopKit
import LoopKitUI
import LoopUI

class OTPSelectionViewController: UITableViewController {
    
    var loopManager: LoopDataManager?
    
    private func generateQRCode(from string: String) -> UIImage? {
        let data = string.data(using: String.Encoding.ascii)
        if let filter = CIFilter(name: "CIQRCodeGenerator") {
            filter.setValue(data, forKey: "inputMessage")
            let transform = CGAffineTransform(scaleX: 6, y: 6)
            if let output = filter.outputImage?.transformed(by: transform) {
                return UIImage(ciImage: output)
            }
        }
        return nil
    }
    
    private func showQRCode() {
       if let image = generateQRCode(from: loopManager!.otpURL) {
           let imageView = UIImageView(image: image)
           imageView.contentMode = .scaleAspectFit
           tableView.tableHeaderView = imageView
           tableView.tableHeaderView!.backgroundColor = tableView.backgroundColor
         }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.rightBarButtonItem =
        UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshQR(_:)))
        
        self.title = "Secret Key"
        tableView.rowHeight = UITableView.automaticDimension
        tableView.alwaysBounceVertical = false
        tableView.tableFooterView = UIView(frame: .zero)
        tableView.tableFooterView!.backgroundColor = UIColor.systemGray6
        tableView.backgroundColor = UIColor.systemGray6
        tableView.separatorStyle = .none
       
        showQRCode()
       
        // center QR code image?
        tableView.contentInset.top = 100
        
        // reuse text button cell view
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
    }
    @objc private func refreshQR(_ sender: UIBarButtonItem) {
        loopManager!.refreshOTPToken()
        self.showQRCode()
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        // Notify observers if the strategy changed since viewDidAppear
       
        super.viewWillDisappear(animated)
    }
    
    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 0
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return " "
    }
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 80
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
   
         // refresh button
         let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell
         cell.textLabel?.text = "Refresh Secret Key"
         cell.textLabel?.textAlignment = .center
         cell.tintColor = .link
         cell.isEnabled = true
         return cell
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.tintColor = tableView.backgroundColor
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = UIColor.clear
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        tableView.deselectRow(at: indexPath, animated: true)
        if(indexPath.row == 0) {
           loopManager!.refreshOTPToken()
           showQRCode()
        }
    }
}
