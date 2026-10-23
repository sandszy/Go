import Foundation

/// 题目类型。对 KataGo 来说，题型只决定题目外面的外框怎么摆（见 `TsumegoFrame`），判对错的标准都一样。
/// 作业纸上的七种题型按外框的摆法归成三种，同一种里外框完全一样。
public enum ProblemGoal: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 对杀、连接、切断：只留棋子外面一路，外框每条边用离它最近的子的颜色，两边在外面都有活棋。
    case capturingRace
    /// 吃子、做活：留印出来的整块，外框都是对方的棋。对方的子跑出去就逃掉了，自己的子只能在里面做活。
    case capture
    /// 逃子、杀棋：留印出来的整块，外框都是做题方的棋。做题方的子跑出去就逃出来了，对方的子只能在里面做活。
    case escape

    public var id: Self { self }

    public var name: String {
        switch self {
        case .capturingRace: "对杀、连接、切断"
        case .capture: "吃子、做活"
        case .escape: "逃子、杀棋"
        }
    }

    /// 摆题时告诉家长这一种的外框是怎么摆的。player 是做题方。
    public func explanation(player: Stone) -> String {
        let me = player.name
        let opponent = player.opponent.name
        switch self {
        case .capturingRace:
            return "外面两边都算活棋，每条边看离它最近的是黑子还是白子，只比棋子这一块。"
        case .capture:
            return "外面都算\(opponent)棋：\(opponent)子跑到外面就逃掉了，\(me)子跑不出去，要在里面做活。"
        case .escape:
            return "外面都算\(me)棋：\(me)子跑到外面就逃出来了，\(opponent)子跑不出去，要在里面做活，做不活就被杀。"
        }
    }

    /// 以前存的题型有七种，按外框的摆法读成现在的三种。
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "capture", "live": self = .capture
        case "escape", "kill": self = .escape
        default: self = .capturingRace
        }
    }
}

/// 一道题：摆好的棋子、谁先下、题目类型。
public struct Problem: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var setup: Board
    public var toPlay: Stone
    public var goal: ProblemGoal
    /// 印在交叉点上的文字，比如印刷题里白子上的"1"。
    public var labels: [Point: String]
    /// 题目印出来的那一块。从照片识别的题目有这个，显示时和作业纸一样；没有时按棋子位置自动算。
    public var region: BoardRegion?

    public init(
        id: UUID = UUID(),
        title: String = "",
        setup: Board = Board(size: 19),
        toPlay: Stone = .black,
        goal: ProblemGoal = .capturingRace,
        labels: [Point: String] = [:],
        region: BoardRegion? = nil
    ) {
        self.id = id
        self.title = title
        self.setup = setup
        self.toPlay = toPlay
        self.goal = goal
        self.labels = labels
        self.region = region
    }

    public var startPosition: Position { Position(board: setup, toPlay: toPlay) }

    private enum CodingKeys: String, CodingKey {
        case id, title, setup, toPlay, goal, labels, region
    }

    /// 以前存的题可能没写题型（那时可以不设），读成默认的对杀。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        setup = try container.decode(Board.self, forKey: .setup)
        toPlay = try container.decode(Stone.self, forKey: .toPlay)
        goal = try container.decodeIfPresent(ProblemGoal.self, forKey: .goal) ?? .capturingRace
        labels = try container.decode([Point: String].self, forKey: .labels)
        region = try container.decodeIfPresent(BoardRegion.self, forKey: .region)
    }
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
