/// 吃子搜索：吃子方能不能吃掉目标块。
/// 只在目标块、要保的块以及它们附近找棋，适合入门题；守方每一步都可以不应（停一手）。
final class CaptureSearch {
    enum Outcome {
        case attackerWon
        case attackerLost
        case open
    }

    enum Result: Equatable {
        /// 吃子方在这么多手（双方合计）之内能吃掉。
        case wins(depth: Int)
        /// 在搜索深度内吃不掉。
        case fails
        /// 超出了节点上限，算不出来。
        case unknown
    }

    let objective: Objective
    let maxDepth: Int
    let nodeLimit: Int
    private(set) var nodes = 0

    private struct Key: Hashable {
        let board: Board
        let toPlay: Stone
        let ko: Point?
    }

    /// 剩余深度不小于 winDepth 时吃子方一定赢，不大于 lossDepth 时一定吃不掉。
    private struct Bound {
        var winDepth = Int.max
        var lossDepth = -1
    }

    private var table: [Key: Bound] = [:]
    private var exhausted = false

    init(objective: Objective, maxDepth: Int, nodeLimit: Int) {
        self.objective = objective
        self.maxDepth = maxDepth
        self.nodeLimit = nodeLimit
    }

    func outcome(_ position: Position) -> Outcome {
        let board = position.board
        if objective.guards.contains(where: { board[$0] != objective.attacker }) { return .attackerLost }
        if objective.targets.contains(where: { board[$0] != objective.defender }) { return .attackerWon }
        if let needed = objective.escapeLiberties,
           objective.targets.allSatisfy({ board.liberties(at: $0).count >= needed }) {
            return .attackerLost
        }
        return .open
    }

    /// 吃子方能不能吃掉，能的话最少要几手。逐步加深：吃得掉时很快找到，吃不掉时主要花在最后一层。
    /// 每次调用都有自己的节点额度，置换表在多次调用之间共用。
    func result(_ position: Position) -> Result {
        switch outcome(position) {
        case .attackerWon: return .wins(depth: 0)
        case .attackerLost: return .fails
        case .open: break
        }
        nodes = 0
        exhausted = false
        for depth in 1...maxDepth {
            let wins = attackerWins(position, depth: depth)
            if exhausted { return .unknown }
            if wins { return .wins(depth: depth) }
        }
        return .fails
    }

    /// 值得考虑的下法：目标块和要保的块的气、能提掉贴着它们的弱块的点。
    /// 吃子题再加上同时贴着目标块两口气的点（枷）。排在前面的是目标块的气。
    func candidates(_ position: Position) -> [Point] {
        let board = position.board
        var groups: [Set<Point>] = []
        for anchor in objective.targets + objective.guards where board[anchor] != nil {
            let group = board.group(at: anchor)
            if !groups.contains(group) { groups.append(group) }
        }

        // 对杀只看双方的气和提子；吃子题还要考虑打吃贴着的弱子、枷这类不直接紧气的手段。
        let isRace = !objective.guards.isEmpty
        var moves = Set<Point>()
        for group in groups {
            moves.formUnion(board.liberties(of: group))
            let color = board[group.first!]!
            for neighbor in board.neighborGroups(of: group, color: color.opponent) {
                let theirs = board.liberties(of: neighbor)
                if theirs.count <= (isRace ? 1 : 2) { moves.formUnion(theirs) }
            }
        }

        let targetLiberties = Set(objective.targets.filter { board[$0] != nil }.flatMap { board.liberties(at: $0) })
        if !isRace && targetLiberties.count == 2 {
            for liberty in targetLiberties {
                for p in board.neighbors(of: liberty) where board[p] == nil && !moves.contains(p) {
                    if board.neighbors(of: p).filter({ targetLiberties.contains($0) }).count >= 2 {
                        moves.insert(p)
                    }
                }
            }
        }

        return moves.sorted { a, b in
            let ra = targetLiberties.contains(a) ? 0 : 1
            let rb = targetLiberties.contains(b) ? 0 : 1
            if ra != rb { return ra < rb }
            return (a.y, a.x) < (b.y, b.x)
        }
    }

    private func attackerWins(_ position: Position, depth: Int) -> Bool {
        switch outcome(position) {
        case .attackerWon: return true
        case .attackerLost: return false
        case .open: break
        }
        if depth <= 0 || exhausted { return false }
        // 对方的块只剩一口气、轮到自己时，直接提掉，不用再展开。
        if position.toPlay == objective.attacker {
            if canCaptureNow(objective.targets, color: objective.defender, in: position) { return true }
        } else {
            if canCaptureNow(objective.guards, color: objective.attacker, in: position) { return false }
        }

        let key = Key(board: position.board, toPlay: position.toPlay, ko: position.koPoint)
        if let bound = table[key] {
            if depth >= bound.winDepth { return true }
            if depth <= bound.lossDepth { return false }
        }
        nodes += 1
        if nodes > nodeLimit {
            exhausted = true
            return false
        }

        let wins: Bool
        if position.toPlay == objective.attacker {
            wins = candidates(position).contains { move in
                guard let next = try? position.playing(move) else { return false }
                return attackerWins(next.position, depth: depth - 1)
            }
        } else {
            let replies = candidates(position).compactMap { try? position.playing($0).position } + [position.passing()]
            wins = replies.allSatisfy { attackerWins($0, depth: depth - 1) }
        }

        guard !exhausted else { return false }
        var bound = table[key] ?? Bound()
        if wins {
            bound.winDepth = min(bound.winDepth, depth)
        } else {
            bound.lossDepth = max(bound.lossDepth, depth)
        }
        table[key] = bound
        return wins
    }

    /// 下在对方块的最后一口气上一定能提，只有打劫时可能不让下。
    private func canCaptureNow(_ anchors: [Point], color: Stone, in position: Position) -> Bool {
        anchors.contains { anchor in
            guard position.board[anchor] == color else { return false }
            let liberties = position.board.liberties(at: anchor)
            return liberties.count == 1 && liberties.first != position.koPoint
        }
    }
}
