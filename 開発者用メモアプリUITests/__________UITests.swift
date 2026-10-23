import XCTest

final class KatachiUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testCanLaunchHomeScreen() throws {
        let app = XCUIApplication()
        app.launch()

        let agreement = app.switches["上記の利用規約とプライバシーポリシーに同意します"]
        if agreement.waitForExistence(timeout: 3) {
            agreement.tap()
            app.buttons["同意して開始"].tap()
        }

        XCTAssertTrue(app.navigationBars["ホーム"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
