/// 做题一方下完一手后的判断。
public enum Verdict: Sendable, Equatable {
    /// 目标已经达成：吃掉了，或者逃出来了。
    case solved
    /// 这一手对，题目还没做完。
    case correct
    /// 这一手不对。
    case wrong
    /// 引擎出错，算不出来。
    case unknown
}

/// 用围棋引擎判题：题目外面摆上外框，比较孩子下的这一手和引擎认为最好的一手差多少目。
///
/// 不需要知道"要吃哪块"，做活、杀棋、连接、切断都能判；只要这一手比最好的下法亏得不多，就算对。
public actor EngineSolver {
    public nonisolated let frame: TsumegoFrame
    private let problem: Problem
    private let engine: any GoEngine
    private var depth: EngineDepth
    private var analyses: [[Point?]: Task<EngineAnalysis, any Error>] = [:]
    /// 孩子还在想时猜着提前算的局面。孩子下了别处，这些就停掉。
    private var guesses: Set<[Point?]> = []
    /// 正等着孩子下的局面。孩子已经下了，就不用再猜这个局面之后的手。
    private var awaiting: [Point?]?
    private var keyStones: [Point: KeyStone]?

    /// 题目要分死活的一个子。
    private struct KeyStone {
        /// 做题方先下时它倒向哪边：1 是归做题方，-1 是归对方。
        var direction: Double
        /// 做题方先下、双方都下最好时，它往 direction 那边倒了多少（归属乘 direction）。
        var best: Double
        /// 这个子是谁的。对方的子 direction 为 1（最后归做题方）就是要吃掉的子。
        var color: Stone
    }

    /// 比最好的下法亏这么多目以内都算对。外框让死活的差别至少有好几目，吃一个子也有两目。
    public static let tolerance = 1.5
    /// 题目要分死活的子，倒向做题方这么多就算定了。外框离得近时，引擎对死活的把握很少到 0.9。
    /// 有的子双方都下最好也定不下来（引擎看是一半一半），这种子只要接近最好的结果就行，见 isFinished。
    static let settled = 0.5
    /// 做题方先下和停一手相比，归属变化超过这个值的子，就是题目要分死活的子。
    static let contested = 0.6
    /// 做题方连着下对这么多手还没做完，也算答对，免得一直下下去。
    static let maxMoves = 15
    /// 轮到孩子时，猜孩子会下引擎最想下的这几手，提前算好。
    static let guessCount = 3

    public init(problem: Problem, engine: any GoEngine, depth: EngineDepth = .standard) {
        self.problem = problem
        self.engine = engine
        self.depth = depth
        frame = TsumegoFrame(problem: problem)
    }

    /// 换一个想的深度，从下一个要算的局面开始用；已经算好的照样用。
    public func setDepth(_ depth: EngineDepth) {
        self.depth = depth
    }

    /// moves 是从题目开始下的每一手，最后一手是做题一方刚下的。
    public func judge(_ moves: [Point?]) async -> Verdict {
        guard let last = moves.last else { return .unknown }
        if let p = last, isOutside(p) { return .wrong }
        dropGuesses(except: moves)
        guard let before = try? await analysis(Array(moves.dropLast())),
              let after = try? await analysis(moves)
        else { return .unknown }

        // 两次搜索各有误差：这一手单独算出的分数，和下这一手之前引擎对它的估计，取对孩子有利的那个。
        var score = -after.scoreLead
        if let estimate = before.candidates.first(where: { $0.move == last && $0.visits * 10 >= (before.candidates.first?.visits ?? 0) }) {
            score = max(score, estimate.scoreLead)
        }
        if before.scoreLead - score > Self.tolerance { return .wrong }
        // 孩子执题目里的另一方时，那一方通常是输的，没有"答对了"，结果定没定看 goalReached。
        guard moves.count % 2 == 1 else { return .correct }
        return await isFinished(moves, after) ? .solved : .correct
    }

    /// 做题方（题目里先下的一方）刚下完 moves 的最后一手，题目的目标是不是已经达成了。
    /// 孩子执另一方、AI 替做题方下的时候用：达成了就是结果定了，孩子这边没办法了。
    public func goalReached(_ moves: [Point?]) async -> Bool {
        guard moves.count % 2 == 1, let after = try? await analysis(moves) else { return false }
        return await isFinished(moves, after)
    }

    /// 这一点在留给题目的区域外面。引擎那边区域外摆着外框，下在这里引擎不认，直接算错。
    public nonisolated func isOutside(_ p: Point) -> Bool {
        !frame.area.contains(p)
    }

    /// 轮到对方时替对方选一手，nil 表示停一手。判题时已经算过这个局面，直接用那次的结果。
    public func reply(_ moves: [Point?]) async -> Point? {
        guard let analysis = try? await analysis(moves) else { return nil }
        return bestMove(in: analysis)
    }

    /// 提前算好这个局面，孩子想下一手的时候引擎就在算了。
    /// 算完再猜孩子会下的几手，也提前算好：猜中了，孩子一下完就能判、对方马上应。
    public func prepare(_ moves: [Point?]) {
        let current = task(for: moves)
        awaiting = moves
        // 开头还要算"做题方停一手"，用来找题目要分死活的子。
        if moves.isEmpty { _ = task(for: [nil]) }
        Task { await guess(after: moves, current) }
    }

    /// 引擎在题目区域里最想下的一手（不算停一手）。以后做提示用；自测里在"最好是停一手"时
    /// 用它代替孩子下，比如对方认输停了一手，孩子要接着去提子。
    public func suggestedMove(_ moves: [Point?]) async -> Point? {
        guard let analysis = try? await analysis(moves) else { return nil }
        return analysis.candidates.lazy.compactMap(\.move).first { frame.area.contains($0) }
    }

    /// 去吃对方要被吃的那块棋：气最少的那块，紧它的一口气（能提就提）。
    /// 对方认输停了一手以后，引擎觉得双方都停也行，没有落子的正解，孩子这时就该去收气、提子。
    public func captureMove(_ moves: [Point?]) async -> Point? {
        guard let keyStones = await findKeyStones(), let position = position(after: moves),
              position.toPlay == problem.toPlay
        else { return nil }
        let opponent = problem.toPlay.opponent
        let board = position.board
        var groups: [Set<Point>] = []
        for (p, stone) in keyStones where stone.color == opponent && stone.direction > 0 && board[p] == opponent {
            if !groups.contains(where: { $0.contains(p) }) { groups.append(board.group(at: p)) }
        }
        for group in groups.sorted(by: { board.liberties(of: $0).count < board.liberties(of: $1).count }) {
            let liberties = board.liberties(of: group).sorted { ($0.y, $0.x) < ($1.y, $1.x) }
            if let move = liberties.first(where: position.isLegal) { return move }
        }
        return nil
    }

    /// 还在棋盘上、要做题方吃掉的对方子有几个。对方认输停一手时，用来提醒孩子去提子。
    public func targetsRemaining(_ moves: [Point?]) async -> Int {
        guard let keyStones = await findKeyStones(), let board = position(after: moves)?.board else { return 0 }
        let opponent = problem.toPlay.opponent
        return keyStones.filter { $0.value.color == opponent && $0.value.direction > 0 && board[$0.key] == opponent }.count
    }

    /// 轮到做题一方时的正解。
    public func correctMoves(_ moves: [Point?]) async -> [Point] {
        guard let analysis = try? await analysis(moves), let best = analysis.candidates.first else { return [] }
        return analysis.candidates.compactMap { candidate in
            guard let move = candidate.move, frame.area.contains(move),
                  candidate.visits * 10 >= best.visits,
                  analysis.scoreLead - candidate.scoreLead <= Self.tolerance
            else { return nil }
            return move
        }
    }

    // MARK: - 内部

    private func analysis(_ moves: [Point?]) async throws -> EngineAnalysis {
        do {
            return try await task(for: moves).value
        } catch {
            // 算失败的不留着，下次重新算。
            analyses[moves] = nil
            throw error
        }
    }

    /// guess 为 true 是猜着提前算的，让给别的请求先算。
    private func task(for moves: [Point?], guess: Bool = false) -> Task<EngineAnalysis, any Error> {
        if let task = analyses[moves] { return task }
        let current = position(after: moves)?.board ?? frame.board
        let query = EngineQuery(
            board: frame.board, firstPlayer: problem.toPlay, moves: moves, komi: frame.komi, maxVisits: depth.visits,
            avoid: avoidedPoints(after: moves, on: current), priority: guess ? -1 : 0
        )
        let engine = engine
        let task = Task { () async throws -> EngineAnalysis in try await engine.analyze(query) }
        analyses[moves] = task
        return task
    }

    /// 等 moves 这个局面算完，按引擎最想下的几手提前算孩子下完以后的局面。
    private func guess(after moves: [Point?], _ current: Task<EngineAnalysis, any Error>) async {
        guard let analysis = try? await current.value, awaiting == moves, let best = analysis.candidates.first else { return }
        let likely = analysis.candidates.lazy
            .filter { $0.visits * 10 >= best.visits }
            .compactMap(\.move)
            .filter { self.frame.area.contains($0) }
            .prefix(Self.guessCount)
        for move in likely {
            let next = moves + [move]
            guard analyses[next] == nil else { continue }
            _ = task(for: next, guess: true)
            guesses.insert(next)
        }
    }

    /// 孩子下了 moves，别的猜测都用不上了，停掉，引擎专心算孩子在等的这个。
    private func dropGuesses(except moves: [Point?]) {
        for guess in guesses where guess != moves {
            analyses[guess]?.cancel()
            analyses[guess] = nil
        }
        guesses = []
        awaiting = nil
    }

    /// 搜索时双方都不下的点。
    /// 开头（第一手，以及找要分死活的子用的"停一手"）只避开离所有棋子两路以外的空地，不漏掉正解。
    /// 下过以后，双方只在要分死活的那几块棋旁边一路以内下：收气、逃、打吃。
    /// 不然对杀一定下来，输的一方会跑去题目区域别处下，双方在空地上来回走，孩子看不明白。
    private func avoidedPoints(after moves: [Point?], on board: Board) -> [Point] {
        let opening = moves.isEmpty || moves == [nil]
        guard !opening, let keyStones, !keyStones.isEmpty else { return frame.distantPoints(on: board) }
        var fight = Set<Point>()
        for p in keyStones.keys where board[p] != nil {
            fight.formUnion(board.group(at: p))
        }
        guard !fight.isEmpty else { return frame.distantPoints(on: board) }
        return frame.area.points.filter { p in
            board[p] == nil && !fight.contains { max(abs($0.x - p.x), abs($0.y - p.y)) <= 1 }
        }
    }

    /// 引擎在题目区域里最想下的一手；它觉得停一手最好时返回 nil。
    private func bestMove(in analysis: EngineAnalysis) -> Point? {
        for candidate in analysis.candidates {
            guard let move = candidate.move else { return nil }
            if frame.area.contains(move) { return move }
        }
        return nil
    }

    /// 题目做完了没有。不是一倒向做题方就算完，要一直下到结果摆在棋盘上：
    /// - 有要吃掉的对方子（对杀、吃子题里对方被吃的那块），要真的提掉；
    /// - 没有要吃的子（做活、救自己的子），要分死活的子都定下来，而且对方已经没有要紧的手：
    ///   引擎让对方停一手，或者对方最想下的地方离这块棋很远。
    /// 做题方下对了 maxMoves 手还没完，也算做完。
    private func isFinished(_ moves: [Point?], _ after: EngineAnalysis) async -> Bool {
        let playerMoves = moves.indices.filter { $0.isMultiple(of: 2) }.count
        if playerMoves >= Self.maxMoves { return true }
        guard let keyStones = await findKeyStones(), !keyStones.isEmpty else { return analysisSuggestsPass(after) }
        guard let board = position(after: moves)?.board else { return false }

        let opponent = problem.toPlay.opponent
        let targets = keyStones.filter { $0.value.color == opponent && $0.value.direction > 0 }.map(\.key)
        if !targets.isEmpty {
            return targets.allSatisfy { board[$0] != opponent }
        }

        let size = problem.setup.size
        // after 是对方要下的局面，归属从对方来看，取反才是做题方的。
        let settled = keyStones.allSatisfy { p, stone in
            let leaning = -(after.ownership[safe: p.y * size + p.x] ?? 0) * stone.direction
            return leaning >= min(Self.settled, stone.best - 0.2)
        }
        guard settled else { return false }
        guard let best = after.candidates.first else { return true }
        guard let move = best.move, frame.area.contains(move) else { return true }
        return !keyStones.keys.contains { max(abs($0.x - move.x), abs($0.y - move.y)) <= 2 }
    }

    /// 题目要分死活的子，以及做题方先下时它们倒向哪边（1 是归做题方，-1 是归对方）。
    /// 做题方先下和停一手让对方先下，这些子的归属差别很大；外面早就活净或死净的子两种情况都一样。
    private func findKeyStones() async -> [Point: KeyStone]? {
        if let keyStones { return keyStones }
        guard let first = try? await analysis([]), let passed = try? await analysis([nil]) else { return nil }
        let size = problem.setup.size
        var stones: [Point: KeyStone] = [:]
        for p in problem.setup.occupiedPoints {
            let index = p.y * size + p.x
            guard let mine = first.ownership[safe: index], let theirs = passed.ownership[safe: index] else { continue }
            // passed 从对方来看，-theirs 才是做题方的；两者之差就是先下一手带来的变化。
            let change = mine + theirs
            if abs(change) >= Self.contested {
                let direction: Double = change > 0 ? 1 : -1
                stones[p] = KeyStone(direction: direction, best: mine * direction, color: problem.setup[p]!)
            }
        }
        keyStones = stones
        return stones
    }

    private func analysisSuggestsPass(_ analysis: EngineAnalysis) -> Bool {
        guard let best = analysis.candidates.first else { return false }
        return best.move == nil || !frame.area.contains(best.move!)
    }

    /// 从题目开始下完 moves 以后的局面。有下不了的手（不该发生）时返回 nil。
    private func position(after moves: [Point?]) -> Position? {
        var position = Position(board: frame.board, toPlay: problem.toPlay)
        for move in moves {
            if let move {
                guard let next = try? position.playing(move) else { return nil }
                position = next.position
            } else {
                position = position.passing()
            }
        }
        return position
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
