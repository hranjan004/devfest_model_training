import XCTest
final class CoyDemoTests: XCTestCase {
 let app=XCUIApplication()
 override func setUpWithError() throws { continueAfterFailure=false }
 func snap(_ n:String) { print("COY_MARK \(n) \(Date().timeIntervalSince1970)"); let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=n;a.lifetime = .keepAlways;add(a) }
 func scroll() { app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.8)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.3))) }
 func reveal(_ e:XCUIElement) { for _ in 0..<10 { if e.exists && e.isHittable { return };scroll() } }
 @MainActor func testNamedMapFlow() throws {
  app.launch();sleep(3);snap("01_coy")
  app.tabBars.buttons["Map"].tap();sleep(3);snap("02_map")
  let search=app.textFields["mapSearch"];search.tap();search.typeText("Sammy\n");sleep(2)
  let sammy=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'mapSighting-legacy-demo-'" )).firstMatch
  XCTAssertTrue(sammy.exists);sammy.tap();sleep(2);snap("03_named_pin")
  app.tabBars.buttons["Identify"].tap();sleep(1)
  app.buttons["choosePhoto"].tap();sleep(2);snap("04_choose")
  let photos=app.images.matching(NSPredicate(format:"label BEGINSWITH 'Photo'"));XCTAssertTrue(photos.firstMatch.waitForExistence(timeout:10));photos.firstMatch.tap()
  XCTAssertTrue(app.staticTexts["Banana slug (genus)"].firstMatch.waitForExistence(timeout:60));sleep(2);snap("05_classify")
  let name=app.textFields["sightingName"];reveal(name);name.tap();name.typeText("Goldie")
  let notes=app.textFields["sightingNotes"];notes.tap();notes.typeText("CC0 photo by Anne Parsons. Demo location.")
  app.toolbars.buttons["Done"].tap();sleep(2);snap("06_name")
  let location=app.descendants(matching:.any).matching(identifier:"sightingLocationMap").firstMatch
  reveal(location);scroll();sleep(1)
  location.coordinate(withNormalizedOffset:CGVector(dx:0.62,dy:0.55)).tap()
  XCTAssertTrue(app.staticTexts["Your marked spot will appear on the sightings map."].exists);sleep(2);snap("07_mark")
  let post=app.buttons["postSighting"];reveal(post);post.tap();sleep(3)
  XCTAssertTrue(app.staticTexts["Goldie"].firstMatch.exists);snap("08_publish")
  app.tabBars.buttons["Map"].tap();app.buttons["Clear map search"].tap()
  search.tap();search.typeText("Goldie\n");sleep(1)
  let row=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'mapSighting-mine-'" )).firstMatch;XCTAssertTrue(row.exists);row.tap();sleep(3);snap("09_linked_map")
  let link=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'mapPost-mine-'" )).firstMatch;XCTAssertTrue(link.exists);link.tap();sleep(2)
  XCTAssertTrue(app.navigationBars["Goldie"].exists);snap("10_post")
  let comment=app.textFields["commentField"];reveal(comment);comment.tap();comment.typeText("Meet Goldie! Found near the trail.")
  app.buttons["postComment"].tap();sleep(2);snap("11_comment")
  app.navigationBars.buttons.element(boundBy:0).tap();sleep(2);snap("12_end")
  app.terminate();app.launch();sleep(2)
  XCTAssertTrue(app.staticTexts["Goldie"].firstMatch.exists)
 }
}
