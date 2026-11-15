//
//  ucscdevfestappUITests.swift
//  ucscdevfestappUITests
//
//  Created by Dean Mcculloh on 11/14/26.
//

import XCTest

/// Smoke test of the main screens. Needs the API running (scripts/run_api.sh) with at
/// least one sighting. Set TEST_RUNNER_SHOTS_DIR to also save a screenshot of each screen.
final class ucscdevfestappUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SHOTS_DIR"] {
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    @MainActor
    func testMainScreens() throws {
        let app = XCUIApplication()
        app.launch()

        let firstPost = app.scrollViews.buttons.firstMatch
        XCTAssertTrue(firstPost.waitForExistence(timeout: 15), "Feed did not load. Is the API running?")
        firstPost.tap()
        XCTAssertTrue(app.staticTexts["Your rating"].waitForExistence(timeout: 5))
        sleep(3)
        snap("detail")
        app.buttons["4 stars"].tap()
        app.swipeUp()
        sleep(1)
        snap("detail_rated")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["New Sighting"].tap()
        XCTAssertTrue(app.buttons["Choose Photo"].waitForExistence(timeout: 5))
        snap("new_sighting")
        app.buttons["Cancel"].tap()

        app.tabBars.buttons["Species"].tap()
        XCTAssertTrue(app.staticTexts["Coyote"].waitForExistence(timeout: 5))
        sleep(3)
        snap("species")
        app.staticTexts["Coyote"].tap()
        sleep(3)
        snap("species_detail")

        app.tabBars.buttons["Ranked"].tap()
        XCTAssertTrue(app.staticTexts["#1"].waitForExistence(timeout: 5))
        snap("ranked")

        app.tabBars.buttons["Map"].tap()
        sleep(4)
        snap("map")
    }
}
