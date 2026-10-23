/// 交给引擎分析的一个局面：起始棋盘加上之后下的每一手。
/// 带着手顺而不是只给最后的棋盘，引擎才知道打劫时哪里不能马上提回。
public struct EngineQuery: Sendable, Hashable {
    public var board: Board
    public var firstPlayer: Stone
    /// nil 表示停一手。
    public var moves: [Point?]
    public var komi: Double
    public var maxVisits: Int
    /// 搜索时双方都不下这些点。题目区域里离棋子很远的空地放在这里，引擎就不会去那里占地。
    public var avoid: [Point]
    /// 好几个请求同时在算时，数大的先算。提前猜着算的请求用负数，让给孩子正在等的那个。
    public var priority: Int

    public init(
        board: Board, firstPlayer: Stone, moves: [Point?] = [], komi: Double, maxVisits: Int, avoid: [Point] = [],
        priority: Int = 0
    ) {
        self.board = board
        self.firstPlayer = firstPlayer
        self.moves = moves
        self.komi = komi
        self.maxVisits = maxVisits
        self.avoid = avoid
        self.priority = priority
    }

    /// 现在轮到谁下。
    public var toPlay: Stone { moves.count.isMultiple(of: 2) ? firstPlayer : firstPlayer.opponent }
}

/// 引擎对一个局面的看法。分数都从轮到下的一方来看，正数表示它领先。
public struct EngineAnalysis: Sendable {
    public struct Candidate: Sendable, Equatable {
        /// nil 表示停一手。
        public var move: Point?
        public var visits: Int
        public var winrate: Double
        public var scoreLead: Double

        public init(move: Point?, visits: Int, winrate: Double, scoreLead: Double) {
            self.move = move
            self.visits = visits
            self.winrate = winrate
            self.scoreLead = scoreLead
        }
    }

    /// 引擎考虑过的下法，最好的在前。
    public var candidates: [Candidate]
    public var winrate: Double
    public var scoreLead: Double
    /// 每个点归谁：1 是轮到下的一方，-1 是对方。按 y * size + x 排。
    public var ownership: [Double]

    public init(candidates: [Candidate], winrate: Double, scoreLead: Double, ownership: [Double]) {
        self.candidates = candidates
        self.winrate = winrate
        self.scoreLead = scoreLead
        self.ownership = ownership
    }
}

public enum EngineError: Error, Sendable {
    /// 模型或引擎没能启动。
    case unavailable(String)
    /// 引擎回了看不懂的结果，或者报了错。
    case failed(String)
}

/// 围棋引擎，比如 KataGo。
public protocol GoEngine: Sendable {
    /// 给家长看的名字，比如"KataGo（GPU）"。
    var name: String { get }
    func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis
}

extension GoEngine {
    public var name: String { "引擎" }
}
