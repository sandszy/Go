import Foundation

/// 题目要达成的目标。
public enum ProblemGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    case capture
    case escape
    case capturingRace
    case connect
    case cut
    case live
    case kill

    public var id: Self { self }

    public var name: String {
        switch self {
        case .capture: "吃子"
        case .escape: "逃子"
        case .capturingRace: "对杀"
        case .connect: "连接"
        case .cut: "切断"
        case .live: "做活"
        case .kill: "杀棋"
        }
    }
}

/// 一道题：摆好的棋子、谁先下、题目目标。
public struct Problem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var setup: Board
    public var toPlay: Stone
    public var goal: ProblemGoal?
    /// 印在交叉点上的文字，比如印刷题里白子上的"1"。
    public var labels: [Point: String]

    public init(
        id: UUID = UUID(),
        title: String = "",
        setup: Board = Board(size: 19),
        toPlay: Stone = .black,
        goal: ProblemGoal? = nil,
        labels: [Point: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.setup = setup
        self.toPlay = toPlay
        self.goal = goal
        self.labels = labels
    }

    public var startPosition: Position { Position(board: setup, toPlay: toPlay) }
}

extension Problem {
    /// 样例作业第 35 页第 7 题：对杀，黑先，题目在左下角，白子"1"是白方刚下的一手。
    public static let sample: Problem = {
        var board = Board(size: 19)
        // 按"从左数第几列、从下数第几行"（都从 0 开始）抄题，再换算成棋盘坐标。
        func at(_ column: Int, _ row: Int) -> Point { Point(column, 18 - row) }
        for (column, row) in [(5, 4), (2, 3), (3, 3), (4, 3), (1, 2), (5, 2), (5, 1)] {
            board[at(column, row)] = .black
        }
        for (column, row) in [(5, 3), (6, 3), (2, 2), (3, 2), (4, 2), (6, 2), (6, 1)] {
            board[at(column, row)] = .white
        }
        return Problem(
            title: "第 35 页第 7 题",
            setup: board,
            toPlay: .black,
            goal: .capturingRace,
            labels: [at(6, 1): "1"]
        )
    }()
}
