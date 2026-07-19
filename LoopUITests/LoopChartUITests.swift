//
//  LoopChartUITests.swift
//  LoopUITests
//
//  Drives a fresh Loop install into a chart-populated state on the simulator:
//  skips onboarding via the debug logo long-press, adds the CGM and pump
//  simulators, backfills glucose history, enables closed loop, and logs a carb
//  entry and a small bolus so all four home-screen charts have content.
//

import XCTest

final class LoopChartUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
    }

    func testSetupLoopForCharts() throws {
        // Write the scenario before the app's first launch so the scenarios
        // manager sees it when it scans its directory during startup.
        injectScenarioFile()

        // XCUIApplication.launch() fails against this app's teamless bundle id
        // ("com..loopkit.Loop"), so launch it from the home screen instead.
        startAppViaSpringboard()
        sleep(3)

        skipOnboardingIfNeeded()
        allowHealthAccessIfNeeded()
        returnToHome()
        snap("01-home-initial")

        addCGMSimulatorIfNeeded()
        snap("02-after-cgm")

        addPumpSimulatorIfNeeded()
        snap("03-after-pump")

        backfillGlucose()
        snap("04-after-backfill")

        enableClosedLoop()
        snap("05-settings-closed-loop")

        logCarbEntry()
        snap("06-after-carbs")

        deliverBolus()
        snap("07-after-bolus")

        loadChartDemoScenario()

        sleep(5)
        snap("08-final-home")

        visitDetailScreens()
    }

    private static let chartDemoScenarioJSON = #"{"glucoseValues": [{"mgdlValue": 133.8, "dateOffset": -21600}, {"mgdlValue": 135.5, "dateOffset": -21300}, {"mgdlValue": 137.6, "dateOffset": -21000}, {"mgdlValue": 139.9, "dateOffset": -20700}, {"mgdlValue": 142.3, "dateOffset": -20400}, {"mgdlValue": 144.8, "dateOffset": -20100}, {"mgdlValue": 146.9, "dateOffset": -19800}, {"mgdlValue": 148.7, "dateOffset": -19500}, {"mgdlValue": 149.8, "dateOffset": -19200}, {"mgdlValue": 150.0, "dateOffset": -18900}, {"mgdlValue": 149.3, "dateOffset": -18600}, {"mgdlValue": 147.5, "dateOffset": -18300}, {"mgdlValue": 144.7, "dateOffset": -18000}, {"mgdlValue": 140.9, "dateOffset": -17700}, {"mgdlValue": 136.4, "dateOffset": -17400}, {"mgdlValue": 131.2, "dateOffset": -17100}, {"mgdlValue": 125.8, "dateOffset": -16800}, {"mgdlValue": 120.3, "dateOffset": -16500}, {"mgdlValue": 115.0, "dateOffset": -16200}, {"mgdlValue": 110.2, "dateOffset": -15900}, {"mgdlValue": 106.0, "dateOffset": -15600}, {"mgdlValue": 102.4, "dateOffset": -15300}, {"mgdlValue": 99.6, "dateOffset": -15000}, {"mgdlValue": 97.5, "dateOffset": -14700}, {"mgdlValue": 96.0, "dateOffset": -14400}, {"mgdlValue": 94.9, "dateOffset": -14100}, {"mgdlValue": 94.0, "dateOffset": -13800}, {"mgdlValue": 93.3, "dateOffset": -13500}, {"mgdlValue": 92.5, "dateOffset": -13200}, {"mgdlValue": 91.5, "dateOffset": -12900}, {"mgdlValue": 90.2, "dateOffset": -12600}, {"mgdlValue": 88.8, "dateOffset": -12300}, {"mgdlValue": 87.2, "dateOffset": -12000}, {"mgdlValue": 85.6, "dateOffset": -11700}, {"mgdlValue": 84.2, "dateOffset": -11400}, {"mgdlValue": 83.1, "dateOffset": -11100}, {"mgdlValue": 82.7, "dateOffset": -10800}, {"mgdlValue": 83.0, "dateOffset": -10500}, {"mgdlValue": 84.2, "dateOffset": -10200}, {"mgdlValue": 86.4, "dateOffset": -9900}, {"mgdlValue": 89.5, "dateOffset": -9600}, {"mgdlValue": 93.6, "dateOffset": -9300}, {"mgdlValue": 98.4, "dateOffset": -9000}, {"mgdlValue": 103.8, "dateOffset": -8700}, {"mgdlValue": 109.5, "dateOffset": -8400}, {"mgdlValue": 115.2, "dateOffset": -8100}, {"mgdlValue": 120.6, "dateOffset": -7800}, {"mgdlValue": 125.6, "dateOffset": -7500}, {"mgdlValue": 130.0, "dateOffset": -7200}, {"mgdlValue": 133.5, "dateOffset": -6900}, {"mgdlValue": 136.2, "dateOffset": -6600}, {"mgdlValue": 138.1, "dateOffset": -6300}, {"mgdlValue": 139.3, "dateOffset": -6000}, {"mgdlValue": 140.0, "dateOffset": -5700}, {"mgdlValue": 140.2, "dateOffset": -5400}, {"mgdlValue": 140.3, "dateOffset": -5100}, {"mgdlValue": 140.4, "dateOffset": -4800}, {"mgdlValue": 140.5, "dateOffset": -4500}, {"mgdlValue": 140.9, "dateOffset": -4200}, {"mgdlValue": 141.4, "dateOffset": -3900}, {"mgdlValue": 142.1, "dateOffset": -3600}, {"mgdlValue": 142.9, "dateOffset": -3300}, {"mgdlValue": 143.6, "dateOffset": -3000}, {"mgdlValue": 143.9, "dateOffset": -2700}, {"mgdlValue": 143.8, "dateOffset": -2400}, {"mgdlValue": 143.0, "dateOffset": -2100}, {"mgdlValue": 141.4, "dateOffset": -1800}, {"mgdlValue": 138.9, "dateOffset": -1500}, {"mgdlValue": 135.5, "dateOffset": -1200}, {"mgdlValue": 131.2, "dateOffset": -900}, {"mgdlValue": 126.3, "dateOffset": -600}, {"mgdlValue": 120.8, "dateOffset": -300}, {"mgdlValue": 115.0, "dateOffset": 0}], "basalDoses": [{"unitsPerHourValue": 0.5, "dateOffset": -21600, "duration": 1800}, {"unitsPerHourValue": 1.2, "dateOffset": -19800, "duration": 1800}, {"unitsPerHourValue": 0.0, "dateOffset": -18000, "duration": 1800}, {"unitsPerHourValue": 2.4, "dateOffset": -16200, "duration": 1800}, {"unitsPerHourValue": 1.8, "dateOffset": -14400, "duration": 1800}, {"unitsPerHourValue": 0.3, "dateOffset": -12600, "duration": 1800}, {"unitsPerHourValue": 1.0, "dateOffset": -10800, "duration": 1800}, {"unitsPerHourValue": 0.05, "dateOffset": -9000, "duration": 1800}, {"unitsPerHourValue": 1.6, "dateOffset": -7200, "duration": 1800}, {"unitsPerHourValue": 0.8, "dateOffset": -5400, "duration": 1800}, {"unitsPerHourValue": 2.0, "dateOffset": -3600, "duration": 1800}, {"unitsPerHourValue": 0.4, "dateOffset": -1800, "duration": 1800}], "bolusDoses": [{"unitsValue": 2.5, "dateOffset": -14400, "deliveryDuration": 100}, {"unitsValue": 1.2, "dateOffset": -7200, "deliveryDuration": 48}, {"unitsValue": 0.6, "dateOffset": -1800, "deliveryDuration": 24}], "carbEntries": [{"gramValue": 45, "dateOffset": -14400, "absorptionTime": 10800}, {"gramValue": 20, "dateOffset": -7200, "absorptionTime": 7200}, {"gramValue": 12, "dateOffset": -1500, "absorptionTime": 10800}]}"#

    /// Writes the chart-demo scenario into the app bundle's Scenarios directory.
    /// The runner and app containers are siblings, and simulator processes can
    /// write to host paths, so this survives xcodebuild's app reinstall.
    private func injectScenarioFile() {
        let fm = FileManager.default
        let applicationsDir = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        guard let containers = try? fm.contentsOfDirectory(at: applicationsDir, includingPropertiesForKeys: nil) else { return }
        for container in containers {
            let loopApp = container.appendingPathComponent("Loop.app")
            guard fm.fileExists(atPath: loopApp.path) else { continue }
            let scenariosDir = loopApp.appendingPathComponent("Scenarios")
            try? fm.createDirectory(at: scenariosDir, withIntermediateDirectories: true)
            try? Self.chartDemoScenarioJSON.data(using: .utf8)?.write(to: scenariosDir.appendingPathComponent("chart-demo.json"))
        }
    }

    /// Opens the debug menu (six quick rotations) and loads the injected chart-demo scenario
    private func loadChartDemoScenario() {

        let device = XCUIDevice.shared
        for _ in 0..<4 {
            device.orientation = .landscapeLeft
            usleep(400_000)
            device.orientation = .portrait
            usleep(400_000)
        }
        sleep(2)
        snap("debug-menu")
        if tapAnything(labeled: "Scenarios", timeout: 6) {
            sleep(1)
            snap("scenario-list")
            if tapAnything(labeled: "chart-demo", timeout: 6) {
                sleep(1)
                _ = tap(app.navigationBars.buttons["Load"], fallback: app.buttons["Load"], timeout: 5)
                sleep(8)
            } else {
                cancelModal()
            }
        }

        // If the debug sheet is still up (e.g. Scenarios missing), dismiss it
        let cancel = app.buttons["Cancel"]
        if cancel.exists, cancel.isHittable {
            cancel.tap()
            sleep(1)
        }
    }

    private func visitDetailScreens() {
        // Glucose chart row -> prediction screen
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.33)).tap()
        sleep(3)
        snap("09-prediction")
        goBack()

        // Carbs chart row -> carb absorption screen
        app.swipeUp()
        sleep(1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).tap()
        sleep(3)
        snap("10-carb-absorption")
        goBack()
    }

    private func goBack() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists, back.isHittable {
            back.tap()
            sleep(1)
        }
    }

    // MARK: - Steps

    private func startAppViaSpringboard() {
        if app.state == .runningForeground {
            return
        }

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.activate()
        sleep(2)

        let icon = springboard.icons["Loop"]
        if icon.waitForExistence(timeout: 5), icon.isHittable {
            icon.tap()
        } else {
            // The icon may be on another page; try the first page after a swipe
            springboard.swipeRight()
            sleep(1)
            if icon.exists, icon.isHittable {
                icon.tap()
            } else {
                XCTFail("Could not find Loop icon on home screen: \(springboard.debugDescription)")
                return
            }
        }

        _ = app.wait(for: .runningForeground, timeout: 20)
    }

    private func skipOnboardingIfNeeded() {
        guard app.staticTexts["Welcome to Loop"].waitForExistence(timeout: 8) else {
            return
        }

        // The logo image is decorative (not in the accessibility tree); long-press by position.
        // Attempt a few vertical offsets to be resilient to layout differences.
        for dy in [0.37, 0.30, 0.44, 0.24] {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: dy)).press(forDuration: 2.8)
            sleep(2)
            if !app.staticTexts["Welcome to Loop"].exists {
                return
            }
        }
        XCTFail("Could not skip onboarding; hierarchy: \(app.debugDescription)")
    }

    /// Clears any blocking permission UI: Springboard system alerts (notifications,
    /// Bluetooth, etc.) and the in-app HealthKit authorization sheet.
    private func allowHealthAccessIfNeeded() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        for _ in 0..<5 {
            var handledSomething = false
            sleep(1)

            // System permission alerts (hosted by Springboard)
            let alert = springboard.alerts.firstMatch
            if alert.exists {
                for label in ["Allow", "Allow While Using App", "OK"] {
                    let button = alert.buttons[label]
                    if button.exists {
                        button.tap()
                        handledSomething = true
                        break
                    }
                }
            }

            // HealthKit authorization flow. iOS 27 presents multiple pages (grant
            // toggles, then historical-data scope); every page has a "Don't Allow".
            if app.staticTexts["Full History"].exists {
                // Historical-data scope page: select Full History once, then wait
                // for Allow to enable. Re-tapping would toggle the selection off.
                let allow = app.buttons["Allow"]
                if !(allow.exists && allow.isEnabled) {
                    app.staticTexts["Full History"].tap()
                }
                for _ in 0..<6 {
                    if allow.exists, allow.isEnabled { break }
                    sleep(1)
                }
                if allow.exists, allow.isEnabled {
                    allow.tap()
                    sleep(1)
                }
                handledSomething = true
            } else if app.buttons["Don't Allow"].exists || app.staticTexts["Health Access"].exists {
                for choice in [app.buttons["Turn On All"], app.staticTexts["Turn On All"], app.cells.staticTexts["Turn On All"]] where choice.exists && choice.isHittable {
                    choice.tap()
                    sleep(1)
                    handledSomething = true
                    break
                }
                for confirm in [app.buttons["Continue"], app.buttons["Allow"]] where confirm.exists && confirm.isHittable && confirm.isEnabled {
                    confirm.tap()
                    sleep(1)
                    handledSomething = true
                    break
                }
            }

            if !handledSomething {
                return
            }
        }
    }

    private func addCGMSimulatorIfNeeded() {
        allowHealthAccessIfNeeded()
        guard tap(app.toolbars.buttons["Settings"], fallback: app.buttons["Settings"], timeout: 8) else { return }
        sleep(2)

        // The Add CGM row may be below the fold; scroll the settings list to find it
        var opened = false
        for _ in 0..<4 {
            if tapAnything(labeled: "Add CGM", timeout: 3) {
                opened = true
                break
            }
            app.swipeUp()
            sleep(1)
        }

        if opened {
            sleep(1)
            snap("cgm-picker")
            _ = scrollPopoverAndTap("CGM Simulator")
            sleep(2)
            allowHealthAccessIfNeeded()
            dismissSheets()
        } else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "cgm-step-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        closeSettings()
    }

    private func addPumpSimulatorIfNeeded() {
        allowHealthAccessIfNeeded()
        // The Settings screen's "Add Pump" row is the most reliable entry point
        guard tap(app.toolbars.buttons["Settings"], fallback: app.buttons["Settings"], timeout: 8) else { return }
        sleep(2)
        if tapAnything(labeled: "Add Pump", timeout: 8) {
            sleep(1)
            snap("pump-action-sheet")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "pump-popover-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            _ = scrollPopoverAndTap("Pump Simulator")
            sleep(2)
            dismissSheets()
        }
        closeSettings()
    }

    /// Taps an option in the device-picker popover, scrolling its list as needed
    @discardableResult
    private func scrollPopoverAndTap(_ label: String) -> Bool {
        for _ in 0..<8 {
            for query in [app.buttons[label], app.cells[label], app.staticTexts[label]] {
                let el = query.firstMatch
                if el.exists, el.isHittable {
                    el.tap()
                    return true
                }
            }
            // Scroll the popover's option list
            let popover = app.popovers.firstMatch
            if popover.exists {
                popover.swipeUp()
            } else {
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.17))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06))
                start.press(forDuration: 0.3, thenDragTo: end)
            }
            usleep(800_000)
        }
        return false
    }

    private func backfillGlucose() {
        allowHealthAccessIfNeeded()
        // Open Settings -> CGM Simulator -> Backfill Glucose -> Save (3h default)
        guard tap(app.toolbars.buttons["Settings"], fallback: app.buttons["Settings"], timeout: 8) else { return }
        sleep(2)
        guard tapAnything(labeled: "CGM Simulator", timeout: 8) else {
            closeSettings()
            return
        }
        sleep(2)
        snap("cgm-settings-sheet")
        if tapAnything(labeled: "Backfill Glucose", timeout: 8) {
            sleep(1)
            _ = tap(app.navigationBars.buttons["Save"], fallback: app.buttons["Save"], timeout: 5)
            sleep(2)
        }
        // Dismiss the CGM settings sheet, then the Settings screen
        _ = tap(app.navigationBars.buttons["Done"], fallback: app.buttons["Done"], timeout: 5)
        sleep(1)
        closeSettings()
    }

    private func enableClosedLoop() {
        allowHealthAccessIfNeeded()
        guard tap(app.toolbars.buttons["Settings"], fallback: app.buttons["Settings"], timeout: 8) else { return }
        sleep(2)
        let toggle = app.switches["Closed Loop"].firstMatch
        if toggle.waitForExistence(timeout: 5), (toggle.value as? String) == "0" {
            toggle.tap()
            sleep(1)
            // Confirm any alert about enabling closed loop
            for confirm in [app.alerts.buttons["Yes"], app.alerts.buttons["Continue"], app.alerts.buttons["OK"]] where confirm.exists {
                confirm.tap()
                break
            }
        }
        closeSettings()
    }

    private func logCarbEntry() {
        allowHealthAccessIfNeeded()
        guard tap(app.toolbars.buttons["Add Meal"], fallback: app.buttons["Add Meal"], timeout: 8) else { return }
        sleep(2)
        // The carb amount field: type a value
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("15")
        }
        snap("carb-entry")
        if !tap(app.buttons["Continue"], fallback: app.staticTexts["Continue"], timeout: 5) {
            cancelModal()
            return
        }
        sleep(3)
        // On the meal bolus screen, save without bolusing if possible
        for label in ["Save without Bolusing", "Save and Deliver", "Save Carb Entry", "Save"] {
            if tapAnything(labeled: label, timeout: 3) {
                sleep(3)
                return
            }
        }
        cancelModal()
    }

    private func deliverBolus() {
        allowHealthAccessIfNeeded()
        guard tap(app.toolbars.buttons["Bolus"], fallback: app.buttons["Bolus"], timeout: 8) else { return }
        sleep(2)
        let field = app.textFields.firstMatch
        if field.waitForExistence(timeout: 5) {
            // Retap until the keyboard actually appears; typing without focus throws
            for _ in 0..<4 {
                field.tap()
                sleep(1)
                if app.keyboards.count > 0 { break }
            }
            if app.keyboards.count > 0 {
                field.typeText("0.5")
            }
        }
        snap("bolus-entry")
        for label in ["Deliver", "Save and Deliver"] {
            if tapAnything(labeled: label, timeout: 3) {
                sleep(4)
                return
            }
        }
        cancelModal()
    }

    // MARK: - Helpers

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func tap(_ primary: XCUIElement, fallback: XCUIElement? = nil, timeout: TimeInterval) -> Bool {
        if primary.waitForExistence(timeout: timeout), primary.isHittable {
            primary.tap()
            return true
        }
        if let fallback = fallback, fallback.exists, fallback.isHittable {
            fallback.tap()
            return true
        }
        return false
    }

    /// Taps the first hittable button, cell, static text, or other element with the given label
    @discardableResult
    private func tapAnything(labeled label: String, timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            for query in [app.buttons, app.cells, app.staticTexts, app.otherElements] {
                let el = query[label].firstMatch
                if el.exists, el.isHittable {
                    el.tap()
                    return true
                }
            }
            usleep(500_000)
        } while Date() < deadline
        return false
    }

    private func dismissSheets() {
        for _ in 0..<2 {
            let done = app.navigationBars.buttons["Done"]
            if done.exists, done.isHittable {
                done.tap()
                sleep(1)
            }
        }
    }

    private func closeSettings() {
        for label in ["Done", "Close"] {
            for query in [app.navigationBars.buttons[label], app.buttons[label]] {
                if query.exists, query.isHittable {
                    query.tap()
                    sleep(1)
                    return
                }
            }
        }
        // Fall back to tapping where the SwiftUI Settings sheet's Done pill sits
        if app.staticTexts["Settings"].exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.87, dy: 0.115)).tap()
            sleep(1)
        }
    }

    /// Dismisses a leftover Settings sheet from a previous partial run
    private func returnToHome() {
        for _ in 0..<3 {
            let done = app.buttons["Done"]
            if app.staticTexts["Settings"].exists, done.exists, done.isHittable {
                done.tap()
                sleep(1)
                continue
            }
            break
        }
    }

    private func cancelModal() {
        for label in ["Cancel", "Close"] {
            let button = app.navigationBars.buttons[label]
            if button.exists, button.isHittable {
                button.tap()
                sleep(1)
                return
            }
        }
    }
}
