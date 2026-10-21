import Testing
@testable import GoCore

@Suite("死活外框")
struct TsumegoFrameTests {
    @Test("第 7 题：题目区域不动，外框两色都活，贴目让两边目数相当")
    func sampleFrame() {
        let problem = Problem.sample
        let frame = TsumegoFrame(problem: problem)
        print(frame.board.diagram, frame.area, frame.komi)
        for p in frame.area.points {
            #expect(frame.board[p] == problem.setup[p])
        }
        #expect(frame.area.width < 19)
        #expect(frame.board.count(of: .black) > 50)
        #expect(frame.board.count(of: .white) > 50)
        // 外框里没有没气的块，也没有和题目里的子贴着的异色子以外的空点。
        #expect(frame.board.groupsWithoutLiberties.isEmpty)
        #expect(abs(frame.komi) < 20)
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
