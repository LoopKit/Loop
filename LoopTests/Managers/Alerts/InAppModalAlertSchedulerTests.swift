//
//  InAppModalAlertSchedulerTests.swift
//  LoopTests
//
//  Created by Rick Pasetto on 4/15/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import LoopKit
import XCTest
@testable import Loop

class InAppModalAlertSchedulerTests: XCTestCase {
    
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
    
    class MockViewController: UIViewController, AlertPresenter {
        var viewControllerPresented: UIViewController?
        var alertDismissed: UIAlertController?
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
        func dismissTopMost(animated: Bool, completion: (() -> Void)?) {
            if autoComplete {
                completion?()
            } else {
                self.completion = completion
            }
        }
        func dismissAlert(_ alertToDismiss: UIAlertController, animated: Bool, completion: (() -> Void)?) {
            alertDismissed = alertToDismiss
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

    static let managerIdentifier = "managerIdentifier"
    let alertIdentifier = Alert.Identifier(managerIdentifier: managerIdentifier, alertIdentifier: "bar")
    let foregroundContent = Alert.Content(title: "FOREGROUND", body: "foreground", acknowledgeActionButtonLabel: "")
    let backgroundContent = Alert.Content(title: "BACKGROUND", body: "background", acknowledgeActionButtonLabel: "")
    
    var mockTimer: Timer?
    var mockTimerTimeInterval: TimeInterval?
    var mockTimerRepeats: Bool?
    var mockAlertManagerResponder: MockAlertManagerResponder!
    var mockViewController: MockViewController!
    var inAppModalAlertScheduler: InAppModalAlertScheduler!
    
    override func setUp() {
        mockAlertManagerResponder = MockAlertManagerResponder()
        mockViewController = MockViewController()

        let newTimerFunc: InAppModalAlertScheduler.TimerFactoryFunction = { timeInterval, repeats, block in
            let timer = Timer(timeInterval: timeInterval, repeats: repeats) { _ in block?() }
            self.mockTimer = timer
            self.mockTimerTimeInterval = timeInterval
            self.mockTimerRepeats = repeats
            return timer
        }
        inAppModalAlertScheduler = InAppModalAlertScheduler(alertPresenter: mockViewController,
                                                            alertManagerResponder: mockAlertManagerResponder,
                                                            newActionFunc: MockAlertAction.init,
                                                            newTimerFunc: newTimerFunc)
    }
    
    func testIssueImmediateAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
    }
    
    func testIssueImmediateAlertWithSound() {
        let soundName = "soundName"
        let alert = Alert(identifier: alertIdentifier,
                          foregroundContent: foregroundContent,
                          backgroundContent: backgroundContent,
                          trigger: .immediate,
                          sound: .sound(name: soundName))
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
    }
    
    func testIssueImmediateAlertWithVibrate() {
        let alert = Alert(identifier: alertIdentifier,
                          foregroundContent: foregroundContent,
                          backgroundContent: backgroundContent,
                          trigger: .immediate,
                          sound: .vibrate)
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        let alertController = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertController)
        XCTAssertEqual("FOREGROUND", alertController?.title)
    }

    func testRemoveImmediateAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        let alertControllerPresented = mockViewController.viewControllerPresented as? UIAlertController
        XCTAssertNotNil(alertControllerPresented)

        var dismissed = false
        inAppModalAlertScheduler.removePresentedAlert(identifier: alert.identifier) {
            dismissed = true
        }

        waitOnMain()
        let alertDimissed = mockViewController.alertDismissed
        XCTAssertNotNil(alertDimissed)
        XCTAssertTrue(dismissed)
    }
    
    func testIssueImmediateAlertTwiceOnlyOneShows() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger:
            .immediate)
        mockViewController.autoComplete = false
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        mockViewController.viewControllerPresented = nil
        inAppModalAlertScheduler.scheduleAlert(alert)
        XCTAssertNil(mockViewController.viewControllerPresented)
    }
    
    func testIssueImmediateAlertWithoutForegroundContentDoesNothing() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: nil, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        XCTAssertNil(mockViewController.viewControllerPresented)
    }
    
    func testIssueImmediateAlertAcknowledgement() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .immediate)
        inAppModalAlertScheduler.scheduleAlert(alert)
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
        inAppModalAlertScheduler.scheduleAlert(alert)
        
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
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        guard let firstTimer = mockTimer else { XCTFail(); return }
        mockTimer = nil
        // This should not schedule another timer
        inAppModalAlertScheduler.scheduleAlert(alert)
        
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
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        XCTAssertNil(mockViewController.viewControllerPresented)
    }
    
    func testRetractAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .delayed(interval: 0.1))
        inAppModalAlertScheduler.scheduleAlert(alert)
        
        waitOnMain()
        XCTAssert(mockTimer?.isValid == true)
        inAppModalAlertScheduler.unscheduleAlert(identifier: alert.identifier)
        
        waitOnMain()
        XCTAssert(mockTimer?.isValid == false)
    }
    
    func testIssueRepeatingAlert() {
        let alert = Alert(identifier: alertIdentifier, foregroundContent: foregroundContent, backgroundContent: backgroundContent, trigger: .repeating(repeatInterval: 0.1))
        mockViewController.autoComplete = false
        inAppModalAlertScheduler.scheduleAlert(alert)
        
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
