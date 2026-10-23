import XCTest

/// 检查 iPad 横屏、竖屏时棋盘和面板的位置。截图作为附件保存在测试结果里。
final class LayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLandscapePutsPanelBesideBoard() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // 不用 KataGo：模拟器上它跑在 CPU 上，判一手要一分多钟；这里测的是界面和做题流程。直接摆上例题。
        app.launchArguments = ["-katagoHardware", "off", "-sampleProblem"]
        app.launch()

        let board = boardElement(in: app)
        let solveTab = app.buttons["做题"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertTrue(solveTab.exists)
        attachScreenshot(named: "横屏-摆题")
        XCTAssertLessThanOrEqual(board.frame.maxX, solveTab.frame.minX, "横屏时面板应该在棋盘右边")

        solveTab.tap()
        XCTAssertTrue(app.staticTexts["轮到黑棋下"].waitForExistence(timeout: 2))
        attachScreenshot(named: "横屏-做题")
    }

    @MainActor
    func testPortraitPutsPanelBelowBoard() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // 不用 KataGo：模拟器上它跑在 CPU 上，判一手要一分多钟；这里测的是界面和做题流程。直接摆上例题。
        app.launchArguments = ["-katagoHardware", "off", "-sampleProblem"]
        app.launch()

        let board = boardElement(in: app)
        let solveTab = app.buttons["做题"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(board.frame.maxY, solveTab.frame.minY, "竖屏时面板应该在棋盘下面")
        attachScreenshot(named: "竖屏-摆题")
    }

    /// 竖屏时面板要滚动，提示必须放在不用滚动就能看到的地方。
    @MainActor
    func testMoveMessageVisibleWithoutScrollingInPortrait() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        // 不用 KataGo：模拟器上它跑在 CPU 上，判一手要一分多钟；这里测的是界面和做题流程。直接摆上例题。
        app.launchArguments = ["-katagoHardware", "off", "-sampleProblem"]
        app.launch()
        app.buttons["做题"].tap()

        // 示例题做题时显示左下角 9×7 路，四周各留 0.75 路。点下数第 2 行、左数第 6 列那颗黑子。
        let board = boardElement(in: app)
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        board.coordinate(withNormalizedOffset: CGVector(dx: 5.75 / 9.5, dy: 5.75 / 7.5)).tap()

        let message = app.staticTexts["这里已经有棋子了"]
        XCTAssertTrue(message.waitForExistence(timeout: 2))
        XCTAssertTrue(message.isHittable, "提示应该不用滚动就能看到")
        attachScreenshot(named: "竖屏-提示")
    }

    /// 第 7 题：下 E2（左数第 5 列、下数第 2 行）判为答对，白棋自动应一手。
    @MainActor
    func testSampleProblemJudgesCorrectAnswer() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        // 不用 KataGo：模拟器上它跑在 CPU 上，判一手要一分多钟；这里测的是界面和做题流程。直接摆上例题。
        app.launchArguments = ["-katagoHardware", "off", "-sampleProblem"]
        app.launch()
        app.buttons["做题"].tap()

        let board = boardElement(in: app)
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        let e2 = board.coordinate(withNormalizedOffset: CGVector(dx: 4.75 / 9.5, dy: 5.75 / 7.5))
        e2.tap()
        e2.tap()

        let praise = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "下得好")).firstMatch
        XCTAssertTrue(praise.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["轮到黑棋下"].waitForExistence(timeout: 5))
        attachScreenshot(named: "横屏-答对")
    }

    @MainActor
    private func boardElement(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "棋盘"))
            .firstMatch
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
