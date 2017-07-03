//
//  KeychainManagerTests.swift
//  Loop
//
//  Created by Nate Racklyeft on 6/26/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import XCTest
@testable import Loop


class KeychainManagerTests: XCTestCase {
    
    func testInvalidData() throws {
        let manager = KeychainManager()

        try manager.setDexcomShareUsername(nil, password: "foo")
        XCTAssertNil(manager.getDexcomShareCredentials())

        try manager.setDexcomShareUsername("foo", password: nil)
        XCTAssertNil(manager.getDexcomShareCredentials())

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

        try manager.setDexcomShareUsername("sugarman", password: "rodriguez")
        let dexcomCredentials = manager.getDexcomShareCredentials()!
        XCTAssertEqual("sugarman", dexcomCredentials.username)
        XCTAssertEqual("rodriguez", dexcomCredentials.password)

        try manager.setDexcomShareUsername(nil, password: nil)
        XCTAssertNil(manager.getDexcomShareCredentials())

        manager.setNightscoutURL(URL(string: "http://mysite.azurewebsites.net")!, secret: "ABCDEFG")
        var nightscoutCredentials = manager.getNightscoutCredentials()!
        XCTAssertEqual(URL(string: "http://mysite.azurewebsites.net")!, nightscoutCredentials.url)
        XCTAssertEqual("ABCDEFG", nightscoutCredentials.secret)

        manager.setNightscoutURL(URL(string: "http://mysite.azurewebsites.net:4443")!, secret: "ABCDEFG")
        nightscoutCredentials = manager.getNightscoutCredentials()!
        XCTAssertEqual(URL(string: "http://mysite.azurewebsites.net:4443")!, nightscoutCredentials.url)
        XCTAssertEqual("ABCDEFG", nightscoutCredentials.secret)

        manager.setNightscoutURL(nil, secret: nil)
        XCTAssertNil(manager.getNightscoutCredentials())

        try manager.setMLabDatabaseName("sugarmandb", APIKey: "rodriguez")
        let mLabCredentials = manager.getMLabCredentials()!
        XCTAssertEqual("sugarmandb", mLabCredentials.databaseName)
        XCTAssertEqual("rodriguez", mLabCredentials.APIKey)

    }
}
