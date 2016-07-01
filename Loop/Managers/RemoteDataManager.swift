//
//  RemoteDataManager.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/29/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import ShareClient


class RemoteDataManager {

    var shareClient: ShareClient?

    func setShareClientUsername(username: String?, password: String?) {

    }

    var nightscoutUploader: NightscoutUploader?

    func setNightscoutURLString(URLString: String?, secret: String?) {

    }

    init() {
        let settings = NSBundle.mainBundle().remoteSettings

        if let username = settings?["ShareAccountName"],
            password = settings?["ShareAccountPassword"]
            where !username.isEmpty && !password.isEmpty
        {
            shareClient = ShareClient(username: username, password: password)
        }

        if let siteURL = settings?["NightscoutSiteURL"],
            APISecret = settings?["NightscoutAPISecret"]
        {
            nightscoutUploader = NightscoutUploader(siteURL: siteURL, APISecret: APISecret)
            nightscoutUploader!.errorHandler = { (error: ErrorType, context: String) -> Void in
                print("Error \(error), while \(context)")
            }
        }
    }

}