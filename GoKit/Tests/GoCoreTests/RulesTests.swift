import Foundation
import Testing
@testable import GoCore

@Suite("落子规则")
struct RulesTests {
    @Test("提掉中间的一个子")
    func capturesSingleStone() throws {
        let position = Position(board: Board(diagram: """
            . X .
            X O X
            . . .
            """))
        let result = try position.playing(Point(1, 2))
        #expect(result.captured == [Point(1, 1)])
        #expect(result.position.board[Point(1, 1)] == nil)
        #expect(result.position.blackCaptures == 1)
        #expect(result.position.toPlay == .white)
    }

    @Test("在角上提子")
    func capturesInCorner() throws {
        let position = Position(board: Board(diagram: """
            O X
            . .
            """))
        let result = try position.playing(Point(0, 1))
        #expect(result.captured == [Point(0, 0)])
    }

    @Test("一次提掉一块")
    func capturesGroup() throws {
        let position = Position(board: Board(diagram: """
            . X X .
            X O O X
            . X . .
            . . . .
            """))
        let result = try position.playing(Point(2, 2))
        #expect(Set(result.captured) == [Point(1, 1), Point(2, 1)])
        #expect(result.position.blackCaptures == 2)
    }

    @Test("下在已有棋子的地方")
    func rejectsOccupiedPoint() {
        let position = Position(board: Board(diagram: """
            X .
            . .
            """), toPlay: .white)
        #expect(throws: MoveError.occupied) { try position.playing(Point(0, 0)) }
    }

    @Test("禁入点不能下")
    func rejectsSuicide() {
        let position = Position(board: Board(diagram: """
            . X .
            X . X
            . X .
            """), toPlay: .white)
        #expect(throws: MoveError.suicide) { try position.playing(Point(1, 1)) }
        #expect(!position.isLegal(Point(1, 1)))
    }

    @Test("能提子的点不算禁入点")
    func captureIsNotSuicide() throws {
        let position = Position(board: Board(diagram: """
            . X O .
            X O . O
            . X O .
            . . . .
            """))
        let result = try position.playing(Point(2, 1))
        #expect(result.captured == [Point(1, 1)])
    }

    @Test("打劫：不能马上提回，隔一手才行")
    func koRule() throws {
        let start = Position(board: Board(diagram: """
            . X O .
            X O . O
            . X O .
            . . . .
            """))
        let afterBlack = try start.playing(Point(2, 1)).position
        #expect(afterBlack.koPoint == Point(1, 1))
        #expect(throws: MoveError.ko) { try afterBlack.playing(Point(1, 1)) }

        // 白棋先在别处下一手，黑棋也下一手，白棋就可以提回来。
        let afterWhite = try afterBlack.playing(Point(0, 3)).position
        #expect(afterWhite.koPoint == nil)
        let afterBlackAgain = try afterWhite.playing(Point(3, 3)).position
        let retake = try afterBlackAgain.playing(Point(1, 1))
        #expect(retake.captured == [Point(2, 1)])
    }

    @Test("停一手解除打劫")
    func passClearsKo() throws {
        let start = Position(board: Board(diagram: """
            . X O .
            X O . O
            . X O .
            . . . .
            """))
        let afterBlack = try start.playing(Point(2, 1)).position
        #expect(afterBlack.passing().koPoint == nil)
        #expect(afterBlack.passing().toPlay == .black)
    }

    @Test("提两子以上不是打劫")
    func multiStoneCaptureIsNotKo() throws {
        let position = Position(board: Board(diagram: """
            . X X .
            X O O X
            . X . .
            . . . .
            """))
        #expect(try position.playing(Point(2, 2)).position.koPoint == nil)
    }
}
