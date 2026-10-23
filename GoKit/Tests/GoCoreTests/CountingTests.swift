import Testing
@testable import GoCore

/// 中国规则数子：活子加只碰到自己颜色的空地，死子先拿掉。
@Suite("数子")
struct CountingTests {
    /// 黑占左边两列，白占右边两列，中间一列两边都碰到。
    private let split = Board(diagram: """
        .X.O.
        .X.O.
        .X.O.
        .X.O.
        .X.O.
        """)

    @Test("空棋盘：双方都是 0")
    func empty() {
        let counted = Board(size: 9).count(dead: [])
        #expect(counted.black == 0)
        #expect(counted.white == 0)
        #expect(counted.owner.isEmpty)
    }

    @Test("黑白各围一块：活子加围住的空点")
    func territory() {
        let counted = split.count(dead: [])
        #expect(counted.black == 10)
        #expect(counted.white == 10)
        #expect(counted.owner[Point(0, 0)] == .black)
        #expect(counted.owner[Point(4, 4)] == .white)
    }

    @Test("公气：两种颜色都碰到的空点不算任何一方")
    func neutral() {
        let counted = split.count(dead: [])
        #expect((0..<5).allSatisfy { counted.owner[Point(2, $0)] == nil })
    }

    @Test("死子先拿掉，那里算给围住它的一方")
    func deadStones() {
        var board = split
        board[Point(0, 3)] = .white
        let alive = board.count(dead: [])
        #expect(alive.black == 5, "不判死子时白子算活的，左边那列空点两种颜色都碰到")
        #expect(alive.white == 11)
        let counted = board.count(dead: [Point(0, 3)])
        #expect(counted.black == 10)
        #expect(counted.white == 10)
        #expect(counted.owner[Point(0, 3)] == .black)

        let result = GameCount(board: board, dead: [Point(0, 3)], komi: 7.5)
        #expect(result.margin == -7.5)
        #expect(result.dead == [Point(0, 3)])
    }
}
