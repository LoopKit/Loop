import XCTest
@testable import Plugins

final class PluginsTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(Plugins().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
