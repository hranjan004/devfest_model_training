import XCTest
final class CoyRankedDemoTests: XCTestCase {
 let app=XCUIApplication()
 override func setUpWithError() throws { continueAfterFailure=false }
 func snap(_ n:String) { print("RANK_MARK \(n) \(Date().timeIntervalSince1970)");let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=n;a.lifetime = .keepAlways;add(a) }
 func scroll() { app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.8)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.3))) }
 @MainActor func testRankedAndMap() throws {
  app.launch();sleep(2)
  app.tabBars.buttons["Ranked"].tap();sleep(2);snap("01_ranked")
  app.buttons["Filter"].tap();app.buttons["Large mammals"].tap();sleep(3);snap("02_mammals")
  app.buttons["ranked-legacy-demo-78f69b003fd5466fb8eeafccf9f53522"].tap();sleep(3)
  XCTAssertTrue(app.navigationBars["Deerly"].exists);snap("03_deer")
  app.navigationBars.buttons.element(boundBy:0).tap();scroll();sleep(2);snap("04_coyote_rank")
  let w=app.buttons["ranked-legacy-demo-32b94b2968864bdaa60436763204100a"];XCTAssertTrue(w.exists);w.tap();sleep(3)
  XCTAssertTrue(app.navigationBars["Whiskers"].exists);snap("05_coyote")
  app.tabBars.buttons["Map"].tap();sleep(1)
  let search=app.textFields["mapSearch"];search.tap();search.typeText("Deerly\n");sleep(1)
  app.buttons["mapSighting-legacy-demo-78f69b003fd5466fb8eeafccf9f53522"].tap();sleep(3);snap("06_deer_map")
  app.buttons["Clear map search"].tap();search.tap();search.typeText("Whiskers\n");sleep(1)
  app.buttons["mapSighting-legacy-demo-32b94b2968864bdaa60436763204100a"].tap();sleep(3);snap("07_coyote_map")
  app.buttons["All"].tap();sleep(3);snap("08_all")
 }
}
