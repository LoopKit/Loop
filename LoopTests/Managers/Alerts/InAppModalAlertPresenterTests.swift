//
//  InAppModalAlertPresenterTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import XCTest
@testable import Loop

class InAppModalAlertPresenterTests: XCTestCase {
    
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
    
    class MockAlertManagerResponder: AlertManagerResponder {
        var identifierAcknowledged: Alert.Identifier?
        func acknowledgeAlert(identifier: Alert.Identifier) {
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
    let alertIdentifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "bar")
    let foregroundContent = Alert.Content(title: "FOREGROUND", body: "foreground", acknowledgeActionButtonLabel: "")
    let backgroundContent = Alert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "")
    
    var mockTimer: Timer?
    var mockTimerTimeInterval: TimeInterval?
    var mockTimerRepeats: Bool?
    var mockAlertManagerResponder: MockAlertManagerResponder!
    var mockViewController: MockViewController!
    var mockSoundPlayer: MockSoundPlayer!
    var inAppModalAlertPresenter: InAppModalAlertPresenter!
    
    override func setUp() {
        mockAlertManagerResponder = MockAlertManagerResponder()
        mockViewController = MockViewController()
        mockSoundPlayer = MockSoundPlayer()
        
        let newTimerFunc: InAppModalAlertPresenter.TimerFactoryFunction = { timeInterval, repeats, block in
            let timer = Timer(timeInterval: timeInterval, repeats: repeats) { _ in block?() }
            self.mockTimer = timer
            self.mockTimerTimeInterval = timeInterval
            self.mockTimerRepeats = repeats
            return timer
        }
        inAppModalAlertPresenter =
            InAppModalAlertPresenter(rootViewController: mockViewController,
                                     alertManagerResponder: mockAlertManagerResponder,
                                     soundPlayer: mockSoundPlayer,
                                     newActionFunc: MockAlertAction.init,
                                     newTimerFunc: newTimerFunc)
    }
    
    func testIssueImmediateAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
        XCTAssertEqual(nil, mockSoundPlayer.urlPlayed?.absoluteString)
        XCTAssertFalse(mockSoundPlayer.vibrateCalled)
    }
    
    func testIssueImmediateAlertWithSound() {
        let soundName = "soundName"
        let alert = Alert(identifier: alertIdentifier,
                          foregroundContent: foregroundContent,
                          backgroundContent: backgroundContent,
                          trigger: .immediate,
                          sound: .sound(name: soundName))
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
        XCTAssertEqual("\(InAppModalAlertPresenterTests.managerIdentifier)-\(soundName)", mockSoundPlayer.urlPlayed?.lastPathComponent)
        XCTAssertTrue(mockSoundPlayer.vibrateCalled)
    }
    
    func testIssueImmediateAlertWithVibrate() {
        let alert = Alert(identifier: alertIdentifier,
                          foregroundContent: foregroundContent,
                          backgroundContent: backgroundContent,
                          trigger: .immediate,
                          sound: .vibrate)
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
        XCTAssertEqual(nil, mockSoundPlayer.urlPlayed?.absoluteString)
        XCTAssertTrue(mockSoundPlayer.vibrateCalled)
    }
    
    func testIssueImmediateAlertWithSilence() {
        let alert = Alert(identifier: alertIdentifier,
                          foregroundContent: foregroundContent,
                          backgroundContent: backgroundContent,
                          trigger: .immediate,
                          sound: .silence)
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
        XCTAssertEqual(nil, mockSoundPlayer.urlPlayed?.absoluteString)
        XCTAssertFalse(mockSoundPlayer.vibrateCalled)
    }
    
    func testRemoveImmediateAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        var dismissed = false
        inAppModalAlertPresenter.removeDeliveredAlert(identifier: alert.identifier) {
            dismissed = true
        }
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertTrue(dismissed)
    }
    
    func testIssueImmediateAlertTwiceOnlyOneShows() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger:
            .immediate)
        mockViewController.autoComplete = false
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        mockViewController.viewControllerPresented = nil
        inAppModalAlertPresenter.issueAlert(alert)
        XCTAssertNil(mockViewController.viewControllerPresented)
    }
    
    func testIssueImmediateAlertWithoutForegroundContentDoesNothing() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        XCTAssertNil(mockViewController.viewControllerPresented)
    }
    
    func testIssueImmediateAlertAcknowledgement() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalAlertPresenter.issueAlert(alert)
        waitOnMain()
        let action = (mockViewController.viewControllerPresented as? UIAlertController)?.actions[0] as? MockAlertAction
        XCTAssertNotNil(action)
        XCTAssertNil(mockAlertManagerResponder.identifierAcknowledged)
        action?.callHandler()
        XCTAssertEqual(alertIdentifier, mockAlertManagerResponder.identifierAcknowledged)
    }
    
    func testIssueDelayedAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        mockViewController.autoComplete = false
        inAppModalAlertPresenter.issueAlert(alert)
        
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
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        mockViewController.autoComplete = false
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        guard let firstTimer = mockTimer else { XCTFail(); return }
        mockTimer = nil
        // This should not schedule another timer
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        XCTAssertNil(mockTimer)
        XCTAssertNil(mockViewController.viewControllerPresented)
        firstTimer.fire()
        
        waitOnMain()
        XCTAssertNil(mockTimer)
        XCTAssertNotNil(mockViewController.viewControllerPresented)
    }
    
    func testIssueDelayedAlertWithoutForegroundContentDoesNothing() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        XCTAssertNil(mockViewController.viewControllerPresented)
    }
    
    func testRetractAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        inAppModalAlertPresenter.issueAlert(alert)
        
        waitOnMain()
        XCTAssert(mockTimer?.isValid == true)
        inAppModalAlertPresenter.retractAlert(identifier: alert.identifier)
        
        waitOnMain()
        XCTAssert(mockTimer?.isValid == false)
    }
    
    func testIssueRepeatingAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .repeating(repeatInterval: 0.1))
        mockViewController.autoComplete = false
        inAppModalAlertPresenter.issueAlert(alert)
        
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
