/// 用围棋引擎判题：题目外面摆上外框，比较孩子下的这一手和引擎认为最好的一手差多少目。
///
/// 和 ProblemSolver 不同，这里不需要知道"要吃哪块"，做活、杀棋、连接、切断都能判；
/// 只要这一手比最好的下法亏得不多，就算对。
public actor EngineSolver {
    public nonisolated let frame: TsumegoFrame
    private let problem: Problem
    private let engine: any GoEngine
    private let visits: Int
    private var analyses: [[Point?]: Task<EngineAnalysis, any Error>] = [:]
    private var keyStones: [Point: Double]?

    /// 比最好的下法亏这么多目以内都算对。外框让死活的差别至少有好几目，吃一个子也有两目。
    public static let tolerance = 1.5
    /// 题目要分死活的子，倒向做题方这么多就算定了。外框离得近时，引擎对死活的把握很少到 0.9。
    static let settled = 0.5
    /// 做题方先下和停一手相比，归属变化超过这个值的子，就是题目要分死活的子。
    static let contested = 0.6

    public init(problem: Problem, engine: any GoEngine, visits: Int = 400) {
        self.problem = problem
        self.engine = engine
        self.visits = visits
        frame = TsumegoFrame(problem: problem)
    }

    /// moves 是从题目开始下的每一手，最后一手是做题一方刚下的。
    public func judge(_ moves: [Point?]) async -> Verdict {
        guard let last = moves.last,
              let before = try? await analysis(Array(moves.dropLast())),
              let after = try? await analysis(moves)
        else { return .unknown }

        // 两次搜索各有误差：这一手单独算出的分数，和下这一手之前引擎对它的估计，取对孩子有利的那个。
        var score = -after.scoreLead
        if let estimate = before.candidates.first(where: { $0.move == last && $0.visits * 10 >= (before.candidates.first?.visits ?? 0) }) {
            score = max(score, estimate.scoreLead)
        }
        if before.scoreLead - score > Self.tolerance { return .wrong }
        return await isFinished(after) ? .solved : .correct
    }

    /// 轮到对方时替对方选一手，nil 表示停一手。判题时已经算过这个局面，直接用那次的结果。
    public func reply(_ moves: [Point?]) async -> Point? {
        guard let analysis = try? await analysis(moves) else { return nil }
        return bestMove(in: analysis)
    }

    /// 提前算好这个局面，孩子想下一手的时候引擎就在算了。
    public func prepare(_ moves: [Point?]) {
        _ = task(for: moves)
        // 开头还要算"做题方停一手"，用来找题目要分死活的子。
        if moves.isEmpty { _ = task(for: [nil]) }
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

    private func task(for moves: [Point?]) -> Task<EngineAnalysis, any Error> {
        if let task = analyses[moves] { return task }
        let query = EngineQuery(board: frame.board, firstPlayer: problem.toPlay, moves: moves, komi: frame.komi, maxVisits: visits)
        let engine = engine
        let task = Task { () async throws -> EngineAnalysis in try await engine.analyze(query) }
        analyses[moves] = task
        return task
    }

    /// 引擎在题目区域里最想下的一手；它觉得停一手最好时返回 nil。
    private func bestMove(in analysis: EngineAnalysis) -> Point? {
        for candidate in analysis.candidates {
            guard let move = candidate.move else { return nil }
            if frame.area.contains(move) { return move }
        }
        return nil
    }

    /// 题目要分死活的那些子都已经倒向做题方，或者引擎让对方停一手，题目就做完了。
    /// 不等对方真的被提掉：死活定了以后，引擎会去抢题目区域里的空地，一直下下去孩子会糊涂。
    private func isFinished(_ after: EngineAnalysis) async -> Bool {
        if analysisSuggestsPass(after) { return true }
        guard let keyStones = await findKeyStones(), !keyStones.isEmpty else { return false }
        let size = problem.setup.size
        // after 是对方要下的局面，归属从对方来看，取反才是做题方的。
        return keyStones.allSatisfy { p, direction in
            -(after.ownership[safe: p.y * size + p.x] ?? 0) * direction >= Self.settled
        }
    }

    /// 题目要分死活的子，以及做题方先下时它们倒向哪边（1 是归做题方，-1 是归对方）。
    /// 做题方先下和停一手让对方先下，这些子的归属差别很大；外面早就活净或死净的子两种情况都一样。
    private func findKeyStones() async -> [Point: Double]? {
        if let keyStones { return keyStones }
        guard let first = try? await analysis([]), let passed = try? await analysis([nil]) else { return nil }
        let size = problem.setup.size
        var stones: [Point: Double] = [:]
        for p in problem.setup.occupiedPoints {
            let index = p.y * size + p.x
            guard let mine = first.ownership[safe: index], let theirs = passed.ownership[safe: index] else { continue }
            // passed 从对方来看，-theirs 才是做题方的；两者之差就是先下一手带来的变化。
            let change = mine + theirs
            if abs(change) >= Self.contested { stones[p] = change > 0 ? 1 : -1 }
        }
        keyStones = stones
        return stones
    }

    private func analysisSuggestsPass(_ analysis: EngineAnalysis) -> Bool {
        guard let best = analysis.candidates.first else { return false }
        return best.move == nil || !frame.area.contains(best.move!)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
