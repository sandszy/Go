import CoreGraphics
import GoCore
import Testing
@testable import GoUI

@MainActor
@Suite("摆题和做题")
struct ProblemEditorModelTests {
    private func emptyModel(size: Int = 9) -> ProblemEditorModel {
        ProblemEditorModel(problem: Problem(setup: Board(size: size)))
    }

    @Test("黑子工具：点空点放子，再点一次拿掉，点白子换成黑子")
    func blackTool() {
        let model = emptyModel()
        let p = Point(2, 2)
        model.tap(p)
        #expect(model.problem.setup[p] == .black)
        model.tap(p)
        #expect(model.problem.setup[p] == nil)
        model.problem.setup[p] = .white
        model.tap(p)
        #expect(model.problem.setup[p] == .black)
    }

    @Test("黑白交替从黑子开始")
    func alternateTool() {
        let model = emptyModel()
        model.select(.alternate)
        model.tap(Point(0, 0))
        model.tap(Point(1, 0))
        model.tap(Point(2, 0))
        #expect(model.problem.setup[Point(0, 0)] == .black)
        #expect(model.problem.setup[Point(1, 0)] == .white)
        #expect(model.problem.setup[Point(2, 0)] == .black)
    }

    @Test("橡皮拿掉棋子和上面的字")
    func eraseTool() {
        let model = ProblemEditorModel(problem: .sample)
        let labeled = Point(6, 17)
        model.select(.erase)
        model.tap(labeled)
        #expect(model.problem.setup[labeled] == nil)
        #expect(model.problem.labels[labeled] == nil)
    }

    @Test("空棋盘直接换大小，有子时先确认")
    func boardSizeChange() {
        let model = emptyModel(size: 9)
        model.requestBoardSize(13)
        #expect(model.problem.setup.size == 13)
        #expect(model.pendingBoardSize == nil)

        model.tap(Point(0, 0))
        model.requestBoardSize(19)
        #expect(model.problem.setup.size == 13)
        #expect(model.pendingBoardSize == 19)

        model.changeBoardSize(to: 19)
        #expect(model.problem.setup == Board(size: 19))
        #expect(model.pendingBoardSize == nil)
    }

    @Test("做题时先显示虚影，点同一点才落子")
    func confirmBeforePlaying() {
        let model = emptyModel()
        model.switchMode(to: .solve)
        model.tap(Point(3, 3))
        #expect(model.ghost == GhostStone(point: Point(3, 3), stone: .black))
        #expect(model.position.board[Point(3, 3)] == nil)

        // 点别的点只是挪动虚影。
        model.tap(Point(4, 4))
        #expect(model.ghost?.point == Point(4, 4))

        model.tap(Point(4, 4))
        #expect(model.position.board[Point(4, 4)] == .black)
        #expect(model.ghost == nil)
        #expect(model.lastMove == Point(4, 4))
        #expect(model.position.toPlay == .white)
    }

    @Test("关掉确认后点一下就落子")
    func playWithoutConfirmation() {
        let model = emptyModel()
        model.switchMode(to: .solve)
        model.confirmMoves = false
        model.tap(Point(3, 3))
        #expect(model.position.board[Point(3, 3)] == .black)
    }

    @Test("不能下的点给出原因")
    func illegalMoveMessage() {
        let model = ProblemEditorModel(problem: Problem(setup: Board(diagram: """
            . X .
            X . X
            . X .
            """), toPlay: .white))
        model.switchMode(to: .solve)
        model.confirmMoves = false
        model.tap(Point(1, 1))
        #expect(model.message == MoveError.suicide.message)
        #expect(model.position.board[Point(1, 1)] == nil)
    }

    @Test("悔棋和重做")
    func undoRedo() {
        let model = emptyModel()
        model.switchMode(to: .solve)
        model.confirmMoves = false
        model.tap(Point(0, 0))
        model.tap(Point(1, 1))
        model.undo()
        #expect(model.position.board[Point(1, 1)] == nil)
        #expect(model.position.toPlay == .white)
        #expect(model.lastMove == Point(0, 0))
        model.redo()
        #expect(model.position.board[Point(1, 1)] == .white)
        #expect(!model.canRedo)

        // 悔棋后下新的一手，重做记录清空。
        model.undo()
        model.tap(Point(2, 2))
        #expect(!model.canRedo)
    }

    @Test("回到摆题再做题，从摆好的局面重新开始")
    func switchingModesRestarts() {
        let model = ProblemEditorModel(problem: .sample)
        model.switchMode(to: .solve)
        model.confirmMoves = false
        model.tap(Point(4, 17))
        model.switchMode(to: .setup)
        model.switchMode(to: .solve)
        #expect(model.position.board == Problem.sample.setup)
        #expect(!model.canUndo)
    }

    @Test("摆题显示全盘，做题只显示局部")
    func regionFollowsMode() {
        let model = ProblemEditorModel(problem: .sample)
        #expect(model.region == .full(size: 19))
        model.switchMode(to: .solve)
        #expect(model.region == BoardRegion(minX: 0, minY: 12, maxX: 8, maxY: 18))
        model.showWholeBoard = true
        #expect(model.region == .full(size: 19))
    }

    @Test("白子被提掉后不再显示它上面的字")
    func labelsHideWhenCaptured() {
        var board = Board(diagram: """
            . X .
            X O X
            . . .
            """)
        board[Point(2, 2)] = nil
        let model = ProblemEditorModel(problem: Problem(setup: board, labels: [Point(1, 1): "1"]))
        model.switchMode(to: .solve)
        model.confirmMoves = false
        #expect(model.displayedLabels == [Point(1, 1): "1"])
        model.tap(Point(1, 2))
        #expect(model.displayedLabels.isEmpty)
    }
}

@Suite("棋盘坐标换算")
struct BoardGeometryTests {
    @Test("交叉点和视图坐标来回换算")
    func roundTrip() {
        let region = BoardRegion(minX: 0, minY: 12, maxX: 8, maxY: 18)
        let geometry = BoardGeometry(region: region, showCoordinates: false, size: CGSize(width: 600, height: 500))
        for p in region.points {
            #expect(geometry.point(at: geometry.position(of: p)) == p)
        }
    }

    @Test("点在格子中间不算")
    func ignoresTapsBetweenPoints() {
        let geometry = BoardGeometry(region: .full(size: 9), showCoordinates: false, size: CGSize(width: 500, height: 500))
        let a = geometry.position(of: Point(3, 3))
        let between = CGPoint(x: a.x + geometry.spacing / 2, y: a.y + geometry.spacing / 2)
        #expect(geometry.point(at: between) == nil)
    }

    @Test("区域外的点击不算")
    func ignoresTapsOutsideRegion() {
        let region = BoardRegion(minX: 0, minY: 12, maxX: 8, maxY: 18)
        let geometry = BoardGeometry(region: region, showCoordinates: false, size: CGSize(width: 600, height: 500))
        let corner = geometry.position(of: Point(8, 12))
        #expect(geometry.point(at: CGPoint(x: corner.x + geometry.spacing, y: corner.y)) == nil)
    }
}
