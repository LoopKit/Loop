//
//  NightscoutService.swift
//  Loop
//
//  Created by Nate Racklyeft on 7/3/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import NightscoutUploadKit
import LoopKit
import LoopKitUI
import os.log


// Encapsulates a Nightscout site and its authentication
public class NightscoutService: ServiceAuthenticationUI {
    public var credentialValues: [String?]
    
    private let log = OSLog(category: "NightscoutService")

    public var credentialFormFields: [ServiceCredential]

    public let title: String = NSLocalizedString("Nightscout", comment: "The title of the Nightscout service")

    public init(siteURL: URL?, APISecret: String?) {
        credentialValues = [
            siteURL?.absoluteString,
            APISecret,
        ]

        credentialFormFields = [
            ServiceCredential(
                title: NSLocalizedString("Site URL", comment: "The title of the nightscout site URL credential"),
                placeholder: NSLocalizedString("https://mysite.herokuapp.com", comment: "The placeholder text for the nightscout site URL credential"),
                isSecret: false,
                keyboardType: .URL
            ),
            ServiceCredential(
                title: NSLocalizedString("API Secret", comment: "The title of the nightscout API secret credential"),
                placeholder: nil,
                isSecret: true,
                keyboardType: .asciiCapable
            )
        ]

        verify { _, _ in }
    }

    // The uploader instance, if credentials are present
    public private(set) var uploader: NightscoutUploader? {
        didSet {
            uploader?.errorHandler = { (error: Error, context: String) -> Void in
                self.log.error("Error: %{public}@, while %{public}@", String(describing: error), context)
            }
        }
    }

    public var siteURL: URL? {
        if let URLString = credentialValues[0], !URLString.isEmpty {
            return URL(string: URLString)
        }

        return nil
    }

    public var APISecret: String? {
        return credentialValues[1]
    }

    public var isAuthorized: Bool = true

    public func verify(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        guard let siteURL = siteURL, let APISecret = APISecret else {
            isAuthorized = false
            completion(false, nil)
            return
        }

        let uploader = NightscoutUploader(siteURL: siteURL, APISecret: APISecret)
        uploader.checkAuth { (error) in
            completion(true, error)
        }
        self.uploader = uploader
    }

    public func reset() {
        isAuthorized = false
        uploader = nil
    }
}
