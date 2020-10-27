//
//  KeychainManagerTests.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
import LoopKit
@testable import Loop


class KeychainManagerTests: XCTestCase {
    
    func testInvalidData() throws {
        let manager = KeychainManager()

        try manager.setUsernamePasswordURLForLabel(nil, password: "foo", url: ServiceURL)
        XCTAssertNil(manager.getUsernamePasswordURLForLabel())

        try manager.setUsernamePasswordURLForLabel("foo", password: nil, url: ServiceURL)
        XCTAssertNil(manager.getUsernamePasswordURLForLabel())

        manager.setNightscoutURL(nil, secret: "foo")
        XCTAssertNil(manager.getNightscoutCredentials())

        manager.setNightscoutURL(URL(string: "foo"), secret: nil)
        XCTAssertNil(manager.getNightscoutCredentials())
    }

    func testValidData() throws {
        let manager = KeychainManager()

        try manager.setAmplitudeAPIKey("1234")
        XCTAssertEqual("1234", manager.getAmplitudeAPIKey())

        try manager.setAmplitudeAPIKey(nil)
        XCTAssertNil(manager.getAmplitudeAPIKey())

        try manager.setUsernamePasswordURLForLabel("sugarman", password: "rodriguez", url: ServiceURL)
        let labelCredentials = manager.getUsernamePasswordURLForLabel()!
        XCTAssertEqual("sugarman", labelCredentials.username)
        XCTAssertEqual("rodriguez", labelCredentials.password)
        XCTAssertEqual(ServiceURL.absoluteString, labelCredentials.url.absoluteString)

        try manager.setUsernamePasswordURLForLabel(nil, password: nil, url: nil)
        XCTAssertNil(manager.getUsernamePasswordURLForLabel())

        manager.setNightscoutURL(URL(string: "http://mysite.herokuapp.com")!, secret: "ABCDEFG")
        var nightscoutCredentials = manager.getNightscoutCredentials()!
        XCTAssertEqual(URL(string: "http://mysite.herokuapp.com")!, nightscoutCredentials.url)
        XCTAssertEqual("ABCDEFG", nightscoutCredentials.secret)

        manager.setNightscoutURL(URL(string: "http://mysite.herokuapp.com:4443")!, secret: "ABCDEFG")
        nightscoutCredentials = manager.getNightscoutCredentials()!
        XCTAssertEqual(URL(string: "http://mysite.herokuapp.com:4443")!, nightscoutCredentials.url)
        XCTAssertEqual("ABCDEFG", nightscoutCredentials.secret)

        manager.setNightscoutURL(nil, secret: nil)
        XCTAssertNil(manager.getNightscoutCredentials())

        try manager.setMLabDatabaseName("sugarmandb", APIKey: "rodriguez")
        let mLabCredentials = manager.getMLabCredentials()!
        XCTAssertEqual("sugarmandb", mLabCredentials.databaseName)
        XCTAssertEqual("rodriguez", mLabCredentials.APIKey)

    }
}


private let ServiceURL = URL(string: "https://share1.dexcom.com")!
private let KeychainLabel = "Label"


extension KeychainManager {
    func setUsernamePasswordURLForLabel(_ username: String?, password: String?, url: URL?) throws {
        let credentials: InternetCredentials?

        if let username = username, let password = password, let url = url {
            credentials = InternetCredentials(username: username, password: password, url: url)
        } else {
            credentials = nil
        }

        // Replace the legacy URL-keyed credentials
        try replaceInternetCredentials(nil, forURL: ServiceURL)

        try replaceInternetCredentials(credentials, forLabel: KeychainLabel)
    }

    func getUsernamePasswordURLForLabel() -> (username: String, password: String, url: URL)? {
        do { // Silence all errors and return nil
            do {
                let credentials = try getInternetCredentials(label: KeychainLabel)

                return (username: credentials.username, password: credentials.password, url: credentials.url)
            } catch KeychainManagerError.copy {
                // Fetch and replace the legacy URL-keyed credentials
                let credentials = try getInternetCredentials(url: ServiceURL)

                try setUsernamePasswordURLForLabel(credentials.username, password: credentials.password, url: credentials.url)

                return (username: credentials.username, password: credentials.password, url: credentials.url)
            }
        } catch {
            return nil
        }
    }
}
