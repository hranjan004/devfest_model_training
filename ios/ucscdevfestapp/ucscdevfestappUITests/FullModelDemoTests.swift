import XCTest

final class FullModelDemoTests: XCTestCase {
    let app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false }
    func snap(_ name: String) {
        print("DEMO_MARK \(name) \(Date().timeIntervalSince1970)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func reveal(_ e: XCUIElement, attempts: Int = 12) {
        for _ in 0..<attempts {
            if e.exists && e.isHittable { break }
            app.swipeUp(velocity: .slow)
        }
    }
    func edgeScroll() {
        app.coordinate(withNormalizedOffset: CGVector(dx:0.02,dy:0.8)).press(forDuration:0.05, thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.3)))
    }
    @MainActor
    func testMapSupplement() throws {
        app.launch(); sleep(2)
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'sighting-mine-'" )).firstMatch.tap()
        sleep(2); snap("map_start")
        for _ in 0..<3 { edgeScroll(); sleep(1) }
        sleep(3); snap("map_centered")
        edgeScroll(); sleep(3); snap("map_credit")
    }
    @MainActor
    func testFullModelWalkthrough() throws {
        app.launch(); sleep(4); snap("01_home")
        app.tabBars.buttons["Species"].tap(); sleep(2); snap("02_catalog")
        // Explore the additional groups, including trees and insects.
        for _ in 0..<5 { app.swipeUp(velocity: .fast) }
        sleep(2); snap("03_expanded_groups")
        for _ in 0..<2 { app.swipeUp(velocity: .fast) }; sleep(2); snap("03b_insects")
        app.tabBars.buttons["Identify"].tap(); sleep(2); snap("04_identify")
        app.buttons["choosePhoto"].tap(); sleep(2); snap("05_photos")
        let photos = app.images.matching(NSPredicate(format:"label BEGINSWITH 'Photo'"))
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout:10)); photos.firstMatch.tap()
        snap("06_inference")
        XCTAssertTrue(app.staticTexts["Banana slug (genus)"].firstMatch.waitForExistence(timeout:60))
        sleep(3); snap("07_result")
        app.swipeUp(velocity: .slow); sleep(2); snap("08_quality")
        let post = app.buttons["postSighting"]; reveal(post); sleep(2); snap("09_location")
        post.tap(); sleep(3)
        XCTAssertTrue(app.staticTexts["You"].firstMatch.exists); snap("10_published")
        let mine = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'sighting-mine-'" )).firstMatch
        XCTAssertTrue(mine.exists); mine.tap(); XCTAssertTrue(app.staticTexts["How sure the model is"].waitForExistence(timeout:5)); sleep(2); snap("11_detail")
        let whereTitle = app.staticTexts["Where"]; reveal(whereTitle)
        app.swipeUp(velocity: .slow); sleep(2); snap("12_map")
        let comment=app.textFields["Add a comment"]; reveal(comment)
        comment.tap(); comment.typeText("Demo photo: Anne Parsons, CC0. Example campus location.")
        app.buttons["Post"].tap(); sleep(2); snap("13_comment")
        app.navigationBars.buttons.element(boundBy:0).tap()
        app.tabBars.buttons["Ranked"].tap(); sleep(3); snap("14_ranked")
        app.buttons["Filter"].tap(); sleep(1)
        app.buttons["Slugs"].tap(); sleep(3); snap("15_slug_ranked")
        app.tabBars.buttons["Home"].tap(); sleep(2); snap("16_end")
        app.terminate(); app.launch(); sleep(2)
        XCTAssertTrue(app.staticTexts["You"].firstMatch.exists, "Posted sighting must survive relaunch")
    }
}
