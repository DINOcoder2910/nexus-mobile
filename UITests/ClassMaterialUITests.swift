import XCTest

/// Get class material on a notebook page (ClassMaterialButton.swift): the button shows on a notebook the G14 fills, and a press shows
/// how the look went. `-NexusTestClassMaterial` answers without a hub (it fills "notebooks/Chem class" and makes "R3.2.8").
final class ClassMaterialUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["-NexusTestClassMaterial"]
        app.launch()
        let sample = app.buttons["Try with sample data"]
        if sample.waitForExistence(timeout: 10) { sample.tap() }
    }

    func step(_ s: String) {
        print("UISTEP \(Date().timeIntervalSince1970) \(s)")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = s
        a.lifetime = .keepAlways
        add(a)
    }

    /// A notebook by that name, opened on its page (made when the sample doesn't have it yet).
    func openNotebook(_ name: String) {
        let row = app.staticTexts[name].firstMatch
        if !row.waitForExistence(timeout: 3) {
            let make = app.buttons["New notebook…"]
            var swipes = 0
            while !make.isHittable && swipes < 6 { app.collectionViews.firstMatch.swipeUp(); swipes += 1 }
            XCTAssertTrue(make.waitForExistence(timeout: 10), "no New notebook… row")
            make.tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            alert.textFields.firstMatch.typeText(name)
            alert.buttons["Make"].tap()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the notebook isn't in the sidebar")
        row.tap()
        step("class-notebook \(name)")
    }

    func testGetClassMaterial() {
        openNotebook("Other class")
        XCTAssertFalse(app.buttons["class-material"].waitForExistence(timeout: 3), "the button shows on a notebook the G14 doesn't fill")
        openNotebook("Chem class")
        let button = app.buttons["class-material"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no Get class material on the notebook it fills")
        step("class-button")
        button.tap()
        let line = app.staticTexts["class-material-line"].firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 10), "no line after the press")
        let done = NSPredicate(format: "label == %@", "New board: R3.2.8.")
        expectation(for: done, evaluatedWith: line)
        waitForExpectations(timeout: 15)
        step("class-done")
    }
}
