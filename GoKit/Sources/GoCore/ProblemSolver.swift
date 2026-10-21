/// 做题一方下完一手后的判断。
public enum Verdict: Sendable, Equatable {
    /// 目标已经达成：吃掉了，或者逃出来了。
    case solved
    /// 这一手对，题目还没做完。
    case correct
    /// 这一手不对。
    case wrong
    /// 超出搜索范围，算不出来。
    case unknown
}

/// 入门题判题器：吃子、逃子、对杀。不支持的题目类型在 init 时返回 nil。
public final class ProblemSolver {
    public let objective: Objective
    private let search: CaptureSearch

    /// maxDepth 是双方合计的手数，不传时对杀搜 12 手、吃子和逃子搜 16 手（征子要多几手）。
    public init?(problem: Problem, maxDepth: Int? = nil, nodeLimit: Int = 100_000) {
        guard let objective = Objective.infer(for: problem) else { return nil }
        self.objective = objective
        let depth = maxDepth ?? (objective.guards.isEmpty ? 16 : 12)
        search = CaptureSearch(objective: objective, maxDepth: depth, nodeLimit: nodeLimit)
    }

    /// 做题一方刚下完一手（轮到对方）时，判断这一手对不对。
    public func judge(_ position: Position) -> Verdict {
        let playerAttacks = objective.player == objective.attacker
        switch search.outcome(position) {
        case .attackerWon: return playerAttacks ? .solved : .wrong
        case .attackerLost: return playerAttacks ? .wrong : .solved
        case .open: break
        }
        switch search.result(position) {
        case .wins: return playerAttacks ? .correct : .wrong
        case .fails: return playerAttacks ? .wrong : .correct
        case .unknown: return .unknown
        }
    }

    /// 轮到做题一方时的所有正解（只在搜索考虑的那些点里找）。
    public func correctMoves(in position: Position) -> [Point] {
        search.candidates(position).filter { move in
            guard let next = try? position.playing(move) else { return false }
            let verdict = judge(next.position)
            return verdict == .correct || verdict == .solved
        }
    }

    /// 轮到对方时，替对方选一手。返回 nil 表示停一手。
    /// 做题一方下对了，就选最顽强的抵抗；下错了，就选能让做题一方失败的那手，让孩子看到后果。
    public func reply(in position: Position) -> Point? {
        let moves = search.candidates(position).compactMap { move -> (Point, CaptureSearch.Result)? in
            guard let next = try? position.playing(move) else { return nil }
            return (move, search.result(next.position))
        }
        if position.toPlay == objective.defender {
            // 守方：有吃不掉的应法就下那手；都会被吃，就选拖得最久的。
            if let escape = moves.first(where: { $0.1 == .fails }) { return escape.0 }
            return moves.max { depth(of: $0.1) < depth(of: $1.1) }?.0
        } else {
            // 吃子方：能吃掉就选最快的；吃不掉就紧目标块最少的气。
            let winning = moves.filter { if case .wins = $0.1 { true } else { false } }
            if let fastest = winning.min(by: { depth(of: $0.1) < depth(of: $1.1) }) { return fastest.0 }
            return moves.first?.0
        }
    }

    private func depth(of result: CaptureSearch.Result) -> Int {
        if case .wins(let depth) = result { return depth }
        return Int.max
    }
}
