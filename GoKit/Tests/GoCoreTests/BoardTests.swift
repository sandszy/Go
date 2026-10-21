import Foundation
import Testing
@testable import GoCore

@Suite("盘面")
struct BoardTests {
    @Test("字符画来回转换不变")
    func diagramRoundTrip() {
        let text = """
            X . O
            . X .
            O . .
            """
        let board = Board(diagram: text)
        #expect(board.size == 3)
        #expect(board[Point(0, 0)] == .black)
        #expect(board[Point(2, 0)] == .white)
        #expect(Board(diagram: board.diagram) == board)
    }

    @Test("数气")
    func countsLiberties() {
        let board = Board(diagram: """
            X X .
            . O .
            . . .
            """)
        #expect(board.liberties(at: Point(0, 0)) == [Point(0, 1), Point(2, 0)])
        #expect(board.liberties(at: Point(1, 1)).count == 3)
        #expect(board.liberties(at: Point(2, 2)).isEmpty)
    }

    @Test("找出没有气的块")
    func findsGroupsWithoutLiberties() {
        let board = Board(diagram: """
            O X .
            X . .
            . . .
            """)
        #expect(board.groupsWithoutLiberties == [[Point(0, 0)]])
    }

    @Test("星位")
    func starPoints() {
        #expect(Board(size: 19).starPoints.count == 9)
        #expect(Set(Board(size: 13).starPoints) == [Point(3, 3), Point(3, 9), Point(9, 3), Point(9, 9), Point(6, 6)])
        #expect(Set(Board(size: 9).starPoints) == [Point(2, 2), Point(2, 6), Point(6, 2), Point(6, 6), Point(4, 4)])
    }

    @Test("坐标写法跳过 I")
    func coordinateNames() {
        #expect(Coordinates.columnLabel(8) == "J")
        #expect(Coordinates.name(of: Point(0, 18), size: 19) == "A1")
        #expect(Coordinates.name(of: Point(3, 3), size: 19) == "D16")
    }
}

@Suite("题目")
struct ProblemTests {
    @Test("样例题的对杀：黑两口气，白三口气")
    func sampleLiberties() {
        let board = Problem.sample.setup
        // 黑棋被围的两子在左数第 5 列、下数第 1、2 行。
        #expect(board.liberties(at: Point(5, 17)) == [Point(4, 17), Point(5, 18)])
        // 白棋中间三子在下数第 2 行。
        #expect(board.liberties(at: Point(3, 16)) == [Point(2, 17), Point(3, 17), Point(4, 17)])
        #expect(board.groupsWithoutLiberties.isEmpty)
    }

    @Test("样例题只显示左下角")
    func sampleRegion() {
        let region = BoardRegion.fitting(Problem.sample.setup)
        #expect(region == BoardRegion(minX: 0, minY: 12, maxX: 8, maxY: 18))
    }

    @Test("空棋盘显示全盘")
    func emptyRegion() {
        #expect(BoardRegion.fitting(Board(size: 9)) == .full(size: 9))
    }

    @Test("区域太窄时向外扩")
    func regionMinimumSpan() {
        var board = Board(size: 19)
        board[Point(9, 9)] = .black
        let region = BoardRegion.fitting(board)
        #expect(region.width == 7)
        #expect(region.height == 7)
        #expect(region.contains(Point(9, 9)))
    }

    @Test("题目可以存成 JSON 再读回来")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Problem.sample)
        let decoded = try JSONDecoder().decode(Problem.self, from: data)
        #expect(decoded == Problem.sample)
    }
}
