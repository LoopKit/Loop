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
    
    var otpManager: OTPManager?
    var currentOTPLabelView: UILabel?
    var createdLabelView: UILabel?
    var qrCodeView: UIImageView?
    var timer: Timer?
    
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
       if let image = generateQRCode(from: otpManager!.otpURL) {
           let headerView = tableView.tableHeaderView!
        
           // current otp
           let otp = otpManager!.otp()
           currentOTPLabelView!.text = "Current OTP: \(otp)"
        
           // current otp
           let created = otpManager!.created
           createdLabelView!.text = "\(created)"
           
           // change current QR Code
           qrCodeView!.removeFromSuperview()
           let newQRCodeView = UIImageView(image: image)
           headerView.addSubview(newQRCodeView)
            
           // arrange
           newQRCodeView.center = CGPoint(x: headerView.frame.size.width/2, y: 300)
           currentOTPLabelView!.frame.size.width = headerView.frame.size.width
           createdLabelView!.frame.size.width = headerView.frame.size.width
           var labelyLoc = 300 - newQRCodeView.frame.size.height / 2 - 50
           currentOTPLabelView!.center = CGPoint(x: headerView.frame.size.width/2, y: labelyLoc)
           labelyLoc = 300 + newQRCodeView.frame.size.height / 2 + 50
           createdLabelView!.center = CGPoint(x: headerView.frame.size.width/2, y: labelyLoc)
        
           // keep new one
           qrCodeView = newQRCodeView
        
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
        
        // create the views
        let headerView = UIView()
        
        qrCodeView = UIImageView()
        qrCodeView!.contentMode = .scaleAspectFit
        
        currentOTPLabelView = UILabel(frame: CGRect(x: 0, y: 0, width: 0, height: 50))
        currentOTPLabelView!.text = "Current OTP: xxxxxx"
        currentOTPLabelView!.font = UIFont.boldSystemFont(ofSize: 24)
        currentOTPLabelView!.textAlignment = .center
      
        createdLabelView = UILabel(frame: CGRect(x: 0, y: 0, width: 0, height: 50))
        createdLabelView!.text = "xxxxxx"
        createdLabelView!.font = UIFont.boldSystemFont(ofSize: 24)
        createdLabelView!.textAlignment = .center
       
        headerView.addSubview(currentOTPLabelView!)
        headerView.addSubview(createdLabelView!)
        headerView.addSubview(qrCodeView!)
                   
        tableView.tableHeaderView = headerView
        tableView.tableHeaderView?.backgroundColor = tableView.backgroundColor
        
        showQRCode()
    
        // reuse text button cell view
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
    }
    @objc private func refreshQR(_ sender: UIBarButtonItem) {
        self.otpManager!.refreshOTPToken()
        self.showQRCode()
    }
    override func viewDidAppear(_ animated: Bool) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
           // current otp
           let otp = self.otpManager!.otp()
           self.currentOTPLabelView!.text = "Current OTP: \(otp)"
        }
        super.viewDidAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {       
        timer?.invalidate()
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
           otpManager!.refreshOTPToken()
           showQRCode()
        }
    }
}
