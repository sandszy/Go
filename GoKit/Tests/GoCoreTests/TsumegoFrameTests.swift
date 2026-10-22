import Testing
@testable import GoCore

@Suite("死活外框")
struct TsumegoFrameTests {
    @Test("第 7 题：题目区域不动，外框两色都活，贴目让两边目数相当")
    func sampleFrame() {
        let problem = Problem.sample
        let frame = TsumegoFrame(problem: problem)
        for p in frame.area.points {
            #expect(frame.board[p] == problem.setup[p])
        }
        #expect(frame.area.width < 19)
        #expect(frame.board.count(of: .black) > 50)
        #expect(frame.board.count(of: .white) > 50)
        // 外框里没有没气的块，也没有和题目里的子贴着的异色子以外的空点。
        #expect(frame.board.groupsWithoutLiberties.isEmpty)
        // 上边的黑框比右边的白框大得多，贴目把差的目数补上；KataGo 的贴目最多 ±150。
        #expect(abs(frame.komi) < 150)
    }

    @Test("对杀题：上边离得最近的是黑子、右边是白子，外框上黑右白")
    func sideColors() {
        let problem = Problem.sample
        let frame = TsumegoFrame(problem: problem)
        let colors = TsumegoFrame.sideColors(for: problem, area: frame.area)
        #expect(colors?[.top] == .black)
        #expect(colors?[.right] == .white)
        #expect(frame.board[Point(0, frame.area.minY - 1)] == .black)
        #expect(frame.board[Point(frame.area.maxX + 1, 18)] == .white)
        #expect(frame.board.groupsWithoutLiberties.isEmpty)
    }

    @Test("9 路棋盘不加外框")
    func smallBoard() {
        var board = Board(size: 9)
        board[Point(2, 2)] = .black
        let frame = TsumegoFrame(problem: Problem(setup: board))
        #expect(frame.board == board)
        #expect(frame.area == .full(size: 9))
    }
}
