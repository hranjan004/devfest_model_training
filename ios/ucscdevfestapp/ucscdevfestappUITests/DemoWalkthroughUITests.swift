//
//  DemoWalkthroughUITests.swift
//  ucscdevfestappUITests
//
//  Drives the app through the screens shown in docs/DEMO.md and saves a screenshot
//  of each step. Run it with scripts/capture_demo.sh, which starts from a clean
//  simulator state (status bar, campus location, sample photo in the library).
//

import XCTest

final class DemoWalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.scrollViews.buttons.firstMatch.waitForExistence(timeout: 20),
                      "Feed did not load. Is the API running?")
        sleep(3)   // let the photos finish loading
    }

    // MARK: Part 1, browsing

    @MainActor
    func test1BrowseTheApp() throws {
        snap("01_home_feed")

        app.buttons["Sort"].tap()
        sleep(1)
        snap("02_sort_menu")
        app.buttons["Top Rated"].tap()
        sleep(2)
        snap("03_home_top_rated")
        app.buttons["Sort"].tap()
        app.buttons["Newest"].tap()
        sleep(1)

        let post = element(app.buttons, labelStartingWith: "Deerly")
        scrollUntilHittable(post)
        post.tap()
        XCTAssertTrue(app.staticTexts["Your rating"].waitForExistence(timeout: 5))
        sleep(3)
        snap("04_post_detail")
        scrollDetailToBottom()
        snap("05_post_detail_comments")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Map"].tap()
        sleep(4)
        snap("06_map_all_sightings")
        if let pin = mapPin(named: "Sammy") {
            pin.tap()
            sleep(2)
            snap("07_map_pin_preview")
        }

        app.tabBars.buttons["Species"].tap()
        XCTAssertTrue(app.staticTexts["Coyote"].waitForExistence(timeout: 5))
        sleep(3)
        snap("08_species_grid")
        app.staticTexts["Coyote"].tap()
        sleep(3)
        snap("09_species_detail")
        app.navigationBars.buttons["Species"].tap()

        app.tabBars.buttons["Ranked"].tap()
        XCTAssertTrue(app.staticTexts["#1"].waitForExistence(timeout: 5))
        sleep(3)
        snap("10_rankings")
    }

    // MARK: Part 2, identify and post a photo

    @MainActor
    func test2IdentifyAndPost() throws {
        app.buttons["New Sighting"].tap()
        allowLocationIfAsked()
        XCTAssertTrue(app.buttons["Choose Photo"].waitForExistence(timeout: 5))
        sleep(1)
        snap("11_new_sighting")

        app.buttons["Choose Photo"].tap()
        sleep(3)
        snap("12_photo_library")
        let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'"))
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10), "Photo picker did not show photos")

        // First a photo that is not one of the 34 species (a built-in simulator photo),
        // to show how the app reports an uncertain result.
        photos.element(boundBy: photos.count - 1).tap()
        let unsure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The model is not sure'")).firstMatch
        if unsure.waitForExistence(timeout: 30) {
            sleep(2)
            snap("13_not_one_of_the_34_species")
        }

        // Then the sample banana slug photo, which is the newest photo in the library.
        let another = app.buttons["Choose Another Photo"]
        XCTAssertTrue(another.waitForExistence(timeout: 10))
        another.tap()
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10))
        sleep(1)
        photos.element(boundBy: 0).tap()
        let top = app.staticTexts["Banana slug (genus)"]
        XCTAssertTrue(top.waitForExistence(timeout: 60), "No identification result")
        XCTAssertFalse(unsure.waitForExistence(timeout: 2), "Expected a confident result for the sample photo")
        sleep(2)
        snap("14_identification_result")

        let name = app.textFields["sightingName"]
        scrollUntilHittable(name)
        type("Goldie", into: name)
        type("Crossing the trail under the redwoods after the rain.", into: app.textFields["sightingNotes"])
        dismissKeyboard()
        snap("15_details_entered")
        app.swipeUp()
        sleep(3)
        snap("16_location_pin")

        app.buttons["Post"].tap()
        let newPost = element(app.buttons, labelStartingWith: "Goldie")
        XCTAssertTrue(newPost.waitForExistence(timeout: 30), "New post did not appear in the feed")
        sleep(3)
        snap("17_posted_in_feed")

        newPost.tap()
        XCTAssertTrue(app.staticTexts["Your rating"].waitForExistence(timeout: 5))
        sleep(3)
        snap("18_new_post_detail")
        scrollDetailToBottom()
        app.buttons["5 stars"].tap()
        type("First banana slug of the season!", into: app.textFields["commentField"])
        dismissKeyboard()
        app.buttons["Post"].tap()
        XCTAssertTrue(app.staticTexts["First banana slug of the season!"].waitForExistence(timeout: 10))
        scrollDetailToBottom()
        snap("19_rated_and_commented")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Species"].tap()
        let slug = app.staticTexts["Banana slug (genus)"]
        scrollUntilHittable(slug)
        sleep(2)
        snap("20_species_with_new_post")

        app.tabBars.buttons["Home"].tap()
        app.buttons["Settings"].tap()
        sleep(1)
        snap("21_settings")
        app.buttons["Done"].tap()
    }

    // MARK: Helpers

    private func element(_ query: XCUIElementQuery, labelStartingWith prefix: String) -> XCUIElement {
        query.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    /// Tap a text field and type, retrying the tap until the field has keyboard focus.
    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<4 {
            field.tap()
            let focused = NSPredicate(format: "hasKeyboardFocus == true")
            if XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: focused, object: field)], timeout: 2) == .completed {
                break
            }
        }
        field.typeText(text)
    }

    /// Scroll a sighting's detail screen to the bottom. The drag starts on the photo,
    /// because a swipe that starts on the map pans the map instead of the page.
    private func scrollDetailToBottom() {
        for _ in 0..<2 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -0.4))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        sleep(2)
    }

    private func dismissKeyboard() {
        let done = app.toolbars.buttons["Done"]
        if done.waitForExistence(timeout: 2) { done.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "Keyboard did not close")
        sleep(1)
    }

    private func scrollUntilHittable(_ element: XCUIElement, attempts: Int = 12) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < attempts {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
        sleep(1)   // let the scroll settle so the next tap lands
    }

    private func mapPin(named name: String) -> XCUIElement? {
        for query in [app.maps.otherElements, app.otherElements, app.buttons] {
            let pin = query[name]
            if pin.waitForExistence(timeout: 2) && pin.isHittable { return pin }
        }
        return nil
    }

    private func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 4) { allow.tap() }
    }

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
}
