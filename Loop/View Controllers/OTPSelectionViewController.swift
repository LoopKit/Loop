//
//  OTPSelectionViewController.swift
//  Loop
//
//  Created by Jose Paredes on 3/26/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import Foundation
import UIKit

let ViewDismissTime: Double = 120
let AlertDismissTime = 10

class OTPSelectionViewController: UIViewController {
    
    var otpManager: OTPManager?
    private var currentOTPLabelView: UILabel?
    private var createdLabelView: UILabel?
    private var qrCodeView: UIImageView?
    private var timer: Timer?
    private var dismissTimer: Timer?
    private var start: Double!
    
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
           //let headerView = tableView.tableHeaderView!
           let theView = self.view!
        
           // current otp
           let otp = otpManager!.otp()
           currentOTPLabelView!.text = "\(otp)"
        
           // current created tag
           let created = otpManager!.created
           createdLabelView!.text = "\(created)"
           
           // change current QR Code
           qrCodeView!.removeFromSuperview()
           let newQRCodeView = UIImageView(image: image)
           theView.addSubview(newQRCodeView)
        
           // arrange
           let  yLoc = theView.frame.size.height / 2
           newQRCodeView.center = CGPoint(x: theView.frame.size.width/2, y: yLoc)
           currentOTPLabelView!.frame.size.width = theView.frame.size.width
           createdLabelView!.frame.size.width = theView.frame.size.width
           var labelyLoc = yLoc - newQRCodeView.frame.size.height / 2 - 50
           currentOTPLabelView!.center = CGPoint(x: theView.frame.size.width/2, y: labelyLoc)
           labelyLoc = yLoc + newQRCodeView.frame.size.height / 2 + 50
           createdLabelView!.center = CGPoint(x: theView.frame.size.width/2, y: labelyLoc)
        
           // keep new QR code
           qrCodeView = newQRCodeView
        
         }
    }
    override func viewDidLoad() {
        self.navigationItem.rightBarButtonItem =
        UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(refreshQR(_:)))
        
        self.navigationItem.leftBarButtonItem =
        UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissView(_:)))
        
        self.title = "Secret Key"

        // create the views
        let theView = UIView()
        
        qrCodeView = UIImageView()
        qrCodeView!.contentMode = .scaleAspectFit
        
        currentOTPLabelView = UILabel(frame: CGRect(x: 0, y: 0, width: 0, height: 50))
        currentOTPLabelView!.text = "xxxxxx"
        currentOTPLabelView!.font = UIFont.boldSystemFont(ofSize: 24)
        currentOTPLabelView!.textAlignment = .center
      
        createdLabelView = UILabel(frame: CGRect(x: 0, y: 0, width: 0, height: 50))
        createdLabelView!.text = "xxxxxx"
        createdLabelView!.font = UIFont.boldSystemFont(ofSize: 24)
        createdLabelView!.textAlignment = .center
       
        theView.addSubview(currentOTPLabelView!)
        theView.addSubview(createdLabelView!)
        theView.addSubview(qrCodeView!)
        theView.backgroundColor = .cellBackgroundColor
        theView.frame.size.width = UIScreen.main.bounds.width
        theView.frame.size.height = UIScreen.main.bounds.height
        self.view = theView
        
        showQRCode()
        
        super.viewDidLoad()
    }
    @objc private func refreshQR(_ sender: UIBarButtonItem) {
        let refreshAlert = UIAlertController(title: "Refresh Secret Key", message: "This action will invalidate the current key. Are you sure you want to refresh? ", preferredStyle: .alert)
        let okAction = UIAlertAction(title: "OK", style: .default ) {_ in
            self.otpManager!.refreshOTPToken()
            self.showQRCode()
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .default ) {_ in
        }
        
        refreshAlert.addAction(okAction)
        refreshAlert.addAction(cancelAction)
        
        // disable views dismiss timer
        self.dismissTimer?.invalidate()
                
        // show alert
        present(refreshAlert, animated: true, completion: nil)
        
        // dismiss after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.seconds(AlertDismissTime) ) {
           refreshAlert.dismiss(animated: true, completion: nil)
            
           // restart view's dismiss timer for what remains of the 120 seconds
           let now = Double(DispatchTime.now().uptimeNanoseconds)/1000000000
           let remaining = ViewDismissTime - (now - self.start) //
            
           // invalidate previous view dismiss timer
           self.dismissTimer?.invalidate()
            
           // set new view dismiss timer
           self.dismissTimer = Timer.scheduledTimer(timeInterval: remaining, target: self, selector: #selector(self.dismissView), userInfo:nil, repeats: false )
            
        }
    }
    @objc private func dismissView(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
    override func viewDidAppear(_ animated: Bool) {
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
           // current otp
           let otp = self.otpManager!.otp()
           self.currentOTPLabelView!.text = "\(otp)"
        }
        
        // allow this view to be displayed for only 120 seconds
        self.dismissTimer = Timer.scheduledTimer(timeInterval: ViewDismissTime, target: self, selector: #selector(dismissView), userInfo:nil, repeats: false )
        
        // keep tract of view view appearing
        self.start = Double(DispatchTime.now().uptimeNanoseconds) / 1000000000
        
        super.viewDidAppear(animated)
    }
    override func viewWillDisappear(_ animated: Bool) {       
        timer?.invalidate()
        dismissTimer?.invalidate()
        super.viewWillDisappear(animated)
    }
}

