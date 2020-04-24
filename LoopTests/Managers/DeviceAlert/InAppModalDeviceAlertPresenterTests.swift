//
//  InAppModalDeviceAlertPresenterTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import XCTest
@testable import Loop

class InAppModalDeviceAlertPresenterTests: XCTestCase {
    
    class MockAlertAction: UIAlertAction {
        typealias Handler = ((UIAlertAction) -> Void)
        var handler: Handler?
        var mockTitle: String?
        var mockStyle: Style
        convenience init(title: String?, style: Style, handler: Handler?) {
            self.init()
            
            mockTitle = title
            mockStyle = style
            self.handler = handler
        }
        override init() {
          mockStyle = .default
          super.init()
        }
        func callHandler() {
            handler?(self)
        }
    }
    
    class MockAlertManagerResponder: DeviceAlertManagerResponder {
        var identifierAcknowledged: DeviceAlert.Identifier?
        func acknowledgeDeviceAlert(identifier: DeviceAlert.Identifier) {
            identifierAcknowledged = identifier
        }
    }
    
    class MockViewController: UIViewController {
        var viewControllerPresented: UIViewController?
        var autoComplete = true
        var completion: (() -> Void)?
        override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
            viewControllerPresented = viewControllerToPresent
            if autoComplete {
                completion?()
            } else {
                self.completion = completion
            }
        }
        func callCompletion() {
            completion?()
        }
    }
    
    class MockSoundPlayer: AlertSoundPlayer {
        var vibrateCalled = false
        func vibrate() {
            vibrateCalled = true
        }
        var urlPlayed: URL?
        func play(url: URL) {
            urlPlayed = url
        }
    }
    
    static let managerIdentifier = "managerIdentifier"
    let alertIdentifier = DeviceAlert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "bar")
    let foregroundContent = DeviceAlert.Content(title: "FOREGROUND", body: "foreground", acknowledgeActionButtonLabel: "")
    let backgroundContent = DeviceAlert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "")
    
    var mockTimer: Timer?
    var mockTimerTimeInterval: TimeInterval?
    var mockTimerRepeats: Bool?
    var mockAlertManagerResponder: MockAlertManagerResponder!
    var mockViewController: MockViewController!
    var mockSoundPlayer: MockSoundPlayer!
    var inAppModalDeviceAlertPresenter: InAppModalDeviceAlertPresenter!
    
    override func setUp() {
        mockAlertManagerResponder = MockAlertManagerResponder()
        mockViewController = MockViewController()
        mockSoundPlayer = MockSoundPlayer()
        
        let newTimerFunc: InAppModalDeviceAlertPresenter.TimerFactoryFunction = { timeInterval, repeats, block in
            let timer = Timer(timeInterval: timeInterval, repeats: repeats) { _ in block?() }
            self.mockTimer = timer
            self.mockTimerTimeInterval = timeInterval
            self.mockTimerRepeats = repeats
            return timer
        }
        inAppModalDeviceAlertPresenter =
            InAppModalDeviceAlertPresenter(rootViewController: mockViewController,
                                           deviceAlertManagerResponder: mockAlertManagerResponder,
                                           soundPlayer: mockSoundPlayer,
                                           newActionFunc: MockAlertAction.init,
                                           newTimerFunc: newTimerFunc)
    }
    
    func testIssueImmediateAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
        XCTAssertEqual(nil, mockSoundPlayer.urlPlayed?.absoluteString)
        XCTAssertFalse(mockSoundPlayer.vibrateCalled)
    }
    
    func testIssueImmediateAlertWithSound() {
        let alert = DeviceAlert(identifier: alertIdentifier,
                                foregroundContent: foregroundContent,
                                backgroundContent: backgroundContent,
                                trigger: .immediate,
                                soundName: "soundName")
        inAppModalDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
        XCTAssertEqual("\(InAppModalDeviceAlertPresenterTests.managerIdentifier)-soundName", mockSoundPlayer.urlPlayed?.lastPathComponent)
        XCTAssertTrue(mockSoundPlayer.vibrateCalled)
    }
    
    func testIssueImmediateAlertWithVibrate() {
        let alert = DeviceAlert(identifier: alertIdentifier,
                                foregroundContent: foregroundContent,
                                backgroundContent: backgroundContent,
                                trigger: .immediate,
                                soundName: .vibrate)
        inAppModalDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
        XCTAssertEqual(nil, mockSoundPlayer.urlPlayed?.absoluteString)
        XCTAssertTrue(mockSoundPlayer.vibrateCalled)
    }
    
    func testIssueImmediateAlertWithSilence() {
        let alert = DeviceAlert(identifier: alertIdentifier,
                                foregroundContent: foregroundContent,
                                backgroundContent: backgroundContent,
                                trigger: .immediate,
                                soundName: .silence)
        inAppModalDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
        XCTAssertEqual(nil, mockSoundPlayer.urlPlayed?.absoluteString)
        XCTAssertFalse(mockSoundPlayer.vibrateCalled)
    }

    func testRemoveImmediateAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        var dismissed = false
        inAppModalDeviceAlertPresenter.removeDeliveredAlert(identifier: alert.identifier) {
            dismissed = true
        }
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertTrue(dismissed)
    }
    
    func testIssueImmediateAlertTwiceOnlyOneShows() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger:
            .immediate)
        mockViewController.autoComplete = false
        inAppModalDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        mockViewController.viewControllerPresented = nil
        inAppModalDeviceAlertPresenter.issueAlert(alert)
        XCTAssertNil(mockViewController.viewControllerPresented)
    }
    
    func testIssueImmediateAlertWithoutForegroundContentDoesNothing() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        XCTAssertNil(mockViewController.viewControllerPresented)
    }
    
    func testIssueImmediateAlertAcknowledgement() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalDeviceAlertPresenter.issueAlert(alert)
        waitOnMain()
        let action = (mockViewController.viewControllerPresented as? UIAlertController)?.actions[0] as? MockAlertAction
        XCTAssertNotNil(action)
        XCTAssertNil(mockAlertManagerResponder.identifierAcknowledged)
        action?.callHandler()
        XCTAssertEqual(alertIdentifier, mockAlertManagerResponder.identifierAcknowledged)
    }
    
    func testIssueDelayedAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        mockViewController.autoComplete = false
        inAppModalDeviceAlertPresenter.issueAlert(alert)
            
        waitOnMain()
        // Timer should be created but won't fire yet
        XCTAssertNil(mockViewController.viewControllerPresented)
        XCTAssertNotNil(mockTimer)
        XCTAssertEqual(0.1, mockTimerTimeInterval)
        XCTAssert(mockTimerRepeats == false)
        mockTimer?.fire()
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
    }
    
    func testIssueDelayedAlertTwiceOnlyOneWorks() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        mockViewController.autoComplete = false
        inAppModalDeviceAlertPresenter.issueAlert(alert)
            
        waitOnMain()
        guard let firstTimer = mockTimer else { XCTFail(); return }
        mockTimer = nil
        // This should not schedule another timer
        inAppModalDeviceAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        XCTAssertNil(mockTimer)
        XCTAssertNil(mockViewController.viewControllerPresented)
        firstTimer.fire()
        
        waitOnMain()
        XCTAssertNil(mockTimer)
        XCTAssertNotNil(mockViewController.viewControllerPresented)
    }
    
    func testIssueDelayedAlertWithoutForegroundContentDoesNothing() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        inAppModalDeviceAlertPresenter.issueAlert(alert)

        waitOnMain()
        XCTAssertNil(mockViewController.viewControllerPresented)
    }

    func testRemovePendingAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        inAppModalDeviceAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        XCTAssert(mockTimer?.isValid == true)
        inAppModalDeviceAlertPresenter.removePendingAlert(identifier: alert.identifier)
        
        waitOnMain()
        XCTAssert(mockTimer?.isValid == false)
    }

    func testIssueRepeatingAlert() {
        let alert = DeviceAlert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .repeating(repeatInterval: 0.1))
        mockViewController.autoComplete = false
        inAppModalDeviceAlertPresenter.issueAlert(alert)
            
        waitOnMain()
        // Timer should be created but won't fire yet
        XCTAssertNil(mockViewController.viewControllerPresented)
        XCTAssertNotNil(mockTimer)
        XCTAssertEqual(0.1, mockTimerTimeInterval)
        XCTAssert(mockTimerRepeats == true)
        mockTimer?.fire()
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
    }
}
