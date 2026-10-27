/// 一手棋的得分。
public enum MoveScore: Sendable, Equatable {
    /// 比引擎认为最好的一手亏了这么多目，不小于 0。
    case loss(Double)
    /// 下在题目区域外面。引擎那边那里是外框，算不了。
    case outside
    /// 引擎出错，算不出来。
    case unknown
}

/// 替对方选的一手。
public enum Reply: Sendable, Equatable {
    /// 引擎认为最好的一手。
    case play(Point)
    /// 引擎觉得停一手最好，没什么好下的，走一步闲棋。
    case idle(Point)
    /// 一个能下的点都没有，只好停一手。
    case pass
}

/// 用围棋引擎给每一手打分：题目外面摆上外框，比较这一手和引擎认为最好的一手差多少目。
///
/// 不判对错，也不判做没做完：不需要知道"要吃哪块"，做活、杀棋、连接、切断都能打分，好不好由人看分数决定。
/// 对弈时不摆外框，看整个棋盘，AI 按棋力放水，下完可以数子。
public actor EngineSolver {
    /// 做题还是对弈。
    public enum Purpose: Sendable {
        /// 摆外框、日本规则、只在要分死活的棋旁边下，没好棋下时走闲棋。
        case problem
        /// 整个棋盘、中国规则、贴 7.5，AI 按棋力选手，可以停一手。
        case game
    }

    public nonisolated let frame: TsumegoFrame
    public nonisolated let purpose: Purpose
    private let problem: Problem
    private let engine: any GoEngine
    private var depth: EngineDepth
    private var strength: AIStrength
    private var random: SplitMix64
    private var analyses: [[Point?]: Task<EngineAnalysis, any Error>] = [:]
    /// 人还在想时猜着提前算的局面。下了别处，这些就停掉。
    private var guesses: Set<[Point?]> = []
    /// 正等着人下的局面。已经下了，就不用再猜这个局面之后的手。
    private var awaiting: [Point?]?
    /// 题目要分死活的子，第一手以后只在它们旁边搜索。
    private var keyStones: Set<Point>?

    /// 亏这么多目以内，界面上分数用绿色，超过用橙色。外框让死活的差别至少有好几目，吃一个子也有两目。
    public static let tolerance = 1.5
    /// 做题方先下和停一手相比，归属变化超过这个值的子，就是题目要分死活的子。
    static let contested = 0.6
    /// 轮到人下时，猜会下引擎最想下的这几手，提前算好。
    static let guessCount = 3
    /// 对弈时白方贴的子数（中国规则）。
    public static let gameKomi = 7.5
    /// 数子时，归对方的把握超过这个值的子算死子；拿不准的算活的。
    static let deadOwnership = 0.5

    /// seed 给测试用：AI 放水时随机抽点，给了种子每次抽得一样。
    public init(
        problem: Problem, engine: any GoEngine, depth: EngineDepth = .standard, purpose: Purpose = .problem,
        strength: AIStrength = .full, seed: UInt64? = nil
    ) {
        self.problem = problem
        self.engine = engine
        self.depth = depth
        self.purpose = purpose
        self.strength = strength
        random = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
        switch purpose {
        case .problem: frame = TsumegoFrame(problem: problem)
        case .game: frame = TsumegoFrame(whole: problem.setup, komi: Self.gameKomi)
        }
    }

    /// 换一个想的深度，从下一个要算的局面开始用；已经算好的照样用。
    public func setDepth(_ depth: EngineDepth) {
        self.depth = depth
    }

    /// 对弈时换一档棋力，从 AI 的下一手开始用。
    public func setStrength(_ strength: AIStrength) {
        self.strength = strength
    }

    /// moves 是从题目开始下的每一手，给最后一手打分。黑白哪一方下的都行，分数从下这手的一方来看。
    public func score(_ moves: [Point?]) async -> MoveScore {
        guard let last = moves.last else { return .unknown }
        if let p = last, isOutside(p) { return .outside }
        dropGuesses(except: moves)
        guard let before = try? await analysis(Array(moves.dropLast())),
              let after = try? await analysis(moves)
        else { return .unknown }
        // 做题时第一手以后要按要分死活的子限制搜索范围，开头那两个局面算完就找出来。
        if purpose == .problem { _ = await findKeyStones() }

        // 两次搜索各有误差：这一手单独算出的分数，和下这一手之前引擎对它的估计，取对下棋一方有利的那个。
        var score = -after.scoreLead
        if let estimate = before.candidates.first(where: { $0.move == last && $0.visits * 10 >= (before.candidates.first?.visits ?? 0) }) {
            score = max(score, estimate.scoreLead)
        }
        // 偶尔算出比"最好的一手"还好，算 0。
        return .loss(max(0, before.scoreLead - score))
    }

    /// 这一点在留给题目的区域外面。引擎那边区域外摆着外框，下在这里引擎不认，不打分。
    public nonisolated func isOutside(_ p: Point) -> Bool {
        !frame.area.contains(p)
    }

    /// 轮到对方时替对方选一手。打分时已经算过这个局面，直接用那次的结果。
    /// 做题时引擎觉得停一手最好也不停，像真人一样走一步闲棋：对方还在下，一直停会让孩子以为出错了。
    /// 对弈时按棋力放水，觉得停一手最好就停，孩子可以数子了。
    public func reply(_ moves: [Point?]) async -> Reply {
        dropGuesses(except: moves)
        if purpose == .problem { _ = await findKeyStones() }
        guard let analysis = try? await analysis(moves), let position = position(after: moves) else { return .pass }
        if purpose == .game { return pick(in: analysis, position: position) }
        if let best = bestMove(in: analysis) { return .play(best) }
        // 先从引擎算过的候选里挑：按引擎排的顺序，亏得最少的在前，通常是收单官、补一手。
        let idle: (Point) -> Bool = { self.frame.area.contains($0) && position.isLegal($0) && !Self.isOwnEye($0, in: position) }
        if let move = analysis.candidates.lazy.compactMap(\.move).first(where: idle) { return .idle(move) }
        // 候选里没有，就挑区域里离棋子最近的空点，像真人一样贴着棋下，不往远处空地扔。
        let board = position.board
        let stones = frame.area.points.filter { board[$0] != nil }
        func distance(_ p: Point) -> Int { stones.map { max(abs($0.x - p.x), abs($0.y - p.y)) }.min() ?? 0 }
        let fallback = frame.area.points.filter(idle).min { (distance($0), $0.y, $0.x) < (distance($1), $1.y, $1.x) }
        return fallback.map(Reply.idle) ?? .pass
    }

    /// 对弈时 AI 的一手。全力下引擎最好的一手；放水时从能下的点里随机抽几个，下其中策略网络最想下的那个。
    /// 不抽填自己眼的点：抽到了也是自杀，看起来太傻。
    private func pick(in analysis: EngineAnalysis, position: Position) -> Reply {
        guard let best = analysis.candidates.first, let bestMove = best.move else { return .pass }
        let size = position.board.size
        func policy(_ p: Point) -> Double { analysis.policy[safe: p.y * size + p.x] ?? -1 }
        guard let picks = strength.picks else { return .play(bestMove) }
        let choices = position.board.allPoints.filter {
            policy($0) > 0 && position.isLegal($0) && !Self.isOwnEye($0, in: position)
        }
        let sample = choices.shuffled(using: &random).prefix(picks)
        guard let move = sample.max(by: { policy($0) < policy($1) }) else { return .play(bestMove) }
        return .play(move)
    }

    /// 对弈结束时数子：引擎觉得归对方的子算死子，再按中国规则数。引擎出错时返回 nil。
    public func count(_ moves: [Point?]) async -> GameCount? {
        dropGuesses(except: moves)
        guard let analysis = try? await analysis(moves), let position = position(after: moves) else { return nil }
        let board = position.board
        var dead = Set<Point>()
        for p in board.occupiedPoints {
            // ownership 从轮到下的一方来看，换成从这颗子来看。
            guard let value = analysis.ownership[safe: p.y * board.size + p.x] else { continue }
            let mine = board[p] == position.toPlay ? value : -value
            if mine <= -Self.deadOwnership { dead.insert(p) }
        }
        return GameCount(board: board, dead: dead, komi: frame.komi)
    }

    /// 填进去就是填自己的眼：四周都是自己的子（棋盘边不算）。
    static func isOwnEye(_ p: Point, in position: Position) -> Bool {
        position.board.neighbors(of: p).allSatisfy { position.board[$0] == position.toPlay }
    }

    /// 提前算好这个局面，人想下一手的时候引擎就在算了。
    /// 算完再猜会下的几手，也提前算好：猜中了，一下完就能打分、对方马上应。
    public func prepare(_ moves: [Point?]) {
        let current = task(for: moves)
        awaiting = moves
        // 做题开头还要算"做题方停一手"，用来找题目要分死活的子。
        if moves.isEmpty, purpose == .problem { _ = task(for: [nil]) }
        Task { await guess(after: moves, current) }
    }

    /// 引擎在题目区域里最想下的一手（不算停一手）。以后做提示用；自测里用它代替孩子下。
    public func suggestedMove(_ moves: [Point?]) async -> Point? {
        guard let analysis = try? await analysis(moves) else { return nil }
        return analysis.candidates.lazy.compactMap(\.move).first { frame.area.contains($0) }
    }

    /// 眼前这个局面的正解：比最好的一手亏得不超过 tolerance 的下法。以后做提示用。
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
        } catch EngineError.interrupted {
            // App 离开前台时被叫停的，不是算不出来：回来用到时重新算一次。
            // 等它的人也被取消了（离开前台时界面取消了正在做的），就不重算，免得在后台又算起来。
            analyses[moves] = nil
            if Task.isCancelled { throw EngineError.interrupted }
            do {
                return try await task(for: moves).value
            } catch {
                analyses[moves] = nil
                throw error
            }
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
        let game = purpose == .game
        let query = EngineQuery(
            board: frame.board, firstPlayer: problem.toPlay, moves: moves, rules: game ? .chinese : .japanese,
            komi: frame.komi, maxVisits: depth.visits, avoid: game ? [] : avoidedPoints(after: moves, on: current),
            priority: guess ? -1 : 0, includePolicy: game
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

    /// 下了 moves，别的猜测都用不上了，停掉，引擎专心算孩子在等的这个。
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
        for p in keyStones where board[p] != nil {
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

    /// 题目要分死活的子：做题方先下和停一手让对方先下，这些子的归属差别很大；
    /// 外面早就活净或死净的子两种情况都一样。
    private func findKeyStones() async -> Set<Point>? {
        if let keyStones { return keyStones }
        guard let first = try? await analysis([]), let passed = try? await analysis([nil]) else { return nil }
        let size = problem.setup.size
        var stones = Set<Point>()
        for p in problem.setup.occupiedPoints {
            let index = p.y * size + p.x
            guard let mine = first.ownership[safe: index], let theirs = passed.ownership[safe: index] else { continue }
            // passed 从对方来看，-theirs 才是做题方的；两者之差就是先下一手带来的变化。
            if abs(mine + theirs) >= Self.contested { stones.insert(p) }
        }
        keyStones = stones
        return stones
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

/// 能给种子的随机数，测试时每次抽得一样。算法是 SplitMix64。
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
