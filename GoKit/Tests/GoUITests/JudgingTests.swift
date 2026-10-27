import Foundation
import GoCore
import Testing
@testable import GoUI

/// 第 7 题的假引擎：开头黑棋领先 10 目、最想下 E2；黑 E2 以后白最想下 F1，黑照样领先 10 目；
/// 黑 D2 以后白最想下 E2，白反过来领先 5 目。别的局面不分胜负，想停一手。
struct SampleEngine: GoEngine {
    func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis {
        let e2 = Point(4, 17), d2 = Point(3, 17), f1 = Point(5, 18)
        let (score, best): (Double, Point?) = switch query.moves {
        case []: (10, e2)
        case [e2]: (-10, f1)
        case [d2]: (5, e2)
        default: (0, nil)
        }
        return EngineAnalysis(candidates: [.init(move: best, visits: 100, winrate: 0.5, scoreLead: score)], winrate: 0.5, scoreLead: score, ownership: [])
    }
}

/// 用第 7 题检查做题时的打分和 AI 陪下：E2 亏 0 目，D2 亏 15 目、会被白棋破解。
@MainActor
@Suite("做题打分")
struct JudgingTests {
    private let e2 = Point(4, 17)
    private let d2 = Point(3, 17)

    private func solvingModel(_ problem: Problem = .sample) -> ProblemEditorModel {
        let model = ProblemEditorModel(problem: problem, engine: SampleEngine())
        model.replyDelay = .zero
        model.confirmMoves = false
        model.switchMode(to: .solve)
        return model
    }

    @Test("下在最好的地方：0 目、绿色，白棋自动应一手，又轮到黑棋")
    func scoresBestMove() async {
        let model = solvingModel()
        model.tap(e2)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "黑 E2：0 目。白棋应在 F1", tone: .success))
        #expect(model.tree.path.count == 3)
        #expect(model.position.toPlay == .black)
        #expect(!model.isThinking)
    }

    @Test("亏得多：分数橙色，不说对错，白棋应出破解的一手")
    func scoresBadMove() async {
        let model = solvingModel()
        model.tap(d2)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "黑 D2：−15 目。白棋应在 E2", tone: .warning))
        #expect(model.lastMove == e2)
        #expect(model.position.toPlay == .black)
    }

    @Test("没有终点：一直下，每手都打分，AI 每手都应")
    func noEnd() async {
        let model = solvingModel()
        model.tap(d2)
        await model.waitUntilIdle()
        for round in 1...3 {
            // 找一个题目区域里能下的空点接着下。
            let area = TsumegoFrame(problem: .sample).area
            let p = area.points.first { model.position.isLegal($0) }!
            model.tap(p)
            await model.waitUntilIdle()
            #expect(model.message?.text.hasPrefix("黑 \(Coordinates.name(of: p, size: 19))：") == true)
            #expect(model.tree.path.count == 3 + 2 * round)
            #expect(model.position.toPlay == .black)
        }
    }

    @Test("AI 没有好棋下时不停一手，走一步闲棋，并说出来")
    func idleMove() async {
        let model = solvingModel()
        model.tap(d2)
        await model.waitUntilIdle()
        model.tap(Point(1, 17))
        await model.waitUntilIdle()
        let idle = try? #require(model.lastMove)
        #expect(model.message?.text == "黑 B2：0 目。白棋没什么好下的了，走一步闲棋：\(idle.map { Coordinates.name(of: $0, size: 19) } ?? "")")
        #expect(model.position.toPlay == .black)
    }

    @Test("关掉 AI 陪下照样打分，白棋不应")
    func scoresWithoutReply() async {
        let model = solvingModel()
        model.autoReply = false
        model.tap(d2)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "黑 D2：−15 目", tone: .warning))
        #expect(model.tree.path.count == 2)
        #expect(model.position.toPlay == .white)
    }

    @Test("关掉 AI 打分：AI 照样应，提示里没有分数；再打开，给最后一手补上分数")
    func replyWithoutScore() async {
        let model = solvingModel()
        model.autoScore = false
        model.tap(e2)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "白棋应在 F1", tone: .info))
        #expect(model.tree.path.count == 3)

        model.restart()
        model.autoReply = false
        model.tap(e2)
        await model.waitUntilIdle()
        #expect(model.message == nil)
        model.autoScore = true
        await model.waitUntilIdle()
        #expect(model.message?.text == "黑 E2：0 目")
        #expect(model.tree.path.count == 2)
    }

    @Test("关掉 AI 陪下：白棋不自动应；再打开，AI 接着应刚下的那手")
    func toggleMidGame() async {
        let model = solvingModel()
        model.autoReply = false
        model.tap(e2)
        await model.waitUntilIdle()
        #expect(model.tree.path.count == 2)
        #expect(model.position.toPlay == .white)
        #expect(model.message?.text == "黑 E2：0 目")

        model.autoReply = true
        await model.waitUntilIdle()
        #expect(model.message?.text == "黑 E2：0 目。白棋应在 F1")
        #expect(model.tree.path.count == 3)
        #expect(model.position.toPlay == .black)
    }

    @Test("AI 想的时候关掉陪下，就不再应，分数照样打")
    func toggleOffWhileThinking() async {
        let model = solvingModel()
        model.replyDelay = .seconds(5)
        model.tap(e2)
        model.autoReply = false
        await model.waitUntilIdle()
        #expect(!model.isThinking)
        #expect(model.tree.path.count == 2)
        #expect(model.message?.text == "黑 E2：0 目")
    }

    @Test("悔棋连同白棋的应手一起退回，再下还能打分")
    func undoAfterWrongMove() async {
        let model = solvingModel()
        model.tap(d2)
        await model.waitUntilIdle()
        model.undo()
        #expect(model.tree.currentID == GameTree.rootID)
        #expect(model.message == nil)

        model.tap(e2)
        await model.waitUntilIdle()
        #expect(model.message?.tone == .success)
    }

    @Test("试过两种下法后，棋盘上标 A、B，面板上能来回切换，分数跟着变")
    func variations() async throws {
        let model = solvingModel()
        model.tap(d2)
        await model.waitUntilIdle()
        model.undo()
        model.tap(e2)
        await model.waitUntilIdle()

        let choices = model.variationChoices
        #expect(choices.map(\.label) == ["变化 A", "变化 B"])
        #expect(choices.last?.isCurrent == true)

        let first = try #require(choices.first)
        model.selectVariation(first.id)
        #expect(model.message?.text == "黑 D2：−15 目。白棋应在 E2")
        #expect(model.position.toPlay == .black)

        model.undo()
        #expect(model.displayedLabels[d2] == "A")
        #expect(model.displayedLabels[e2] == "B")
    }

    @Test("删掉下错的那个变化")
    func deleteVariation() async {
        let model = solvingModel()
        model.tap(d2)
        await model.waitUntilIdle()
        model.undo()
        model.tap(e2)
        await model.waitUntilIdle()
        model.selectVariation(model.variationChoices[0].id)

        model.deleteCurrentVariation()
        #expect(model.tree.currentID == GameTree.rootID)
        #expect(model.variationChoices.isEmpty)
        #expect(model.tree.current.children.count == 1)
    }

    @Test("AI 打分和 AI 陪下都关：不用引擎，黑白轮流自由下，提了子才提示")
    func freePlayWhenBothOff() async {
        let model = solvingModel()
        model.autoScore = false
        model.autoReply = false
        model.tap(d2)
        #expect(!model.isThinking)
        await model.waitUntilIdle()
        #expect(model.position.toPlay == .white)
        #expect(model.message == nil)
    }

    @Test("提了子：分数后面写提掉几个子")
    func captureNote() async {
        // 白子 D2 只剩一口气，黑下 D1 提掉。
        var board = Board(size: 19)
        board[Point(3, 17)] = .white
        for p in [Point(2, 17), Point(4, 17), Point(3, 16)] { board[p] = .black }
        let model = solvingModel(Problem(setup: board))
        model.tap(Point(3, 18))
        await model.waitUntilIdle()
        #expect(model.message?.text.hasPrefix("黑 D1：−10 目，提掉 1 个子。白棋没什么好下的了，走一步闲棋：") == true)
    }

    @Test("分数的写法：负数、一位小数，不到 0.05 目写 0")
    func scoreFormat() {
        #expect(ProblemEditorModel.scoreText(0) == "0 目")
        #expect(ProblemEditorModel.scoreText(0.04) == "0 目")
        #expect(ProblemEditorModel.scoreText(2.34) == "−2.3 目")
        #expect(ProblemEditorModel.scoreText(14.5) == "−14.5 目")
        #expect(ProblemEditorModel.scoreText(15) == "−15 目")
    }

    @Test("没有引擎：不打分，两个开关都用不了，自己两边下")
    func withoutEngine() async {
        let model = ProblemEditorModel(problem: .sample)
        #expect(!model.canJudge)
        #expect(!model.hasEngine)
        #expect(model.judgeSummary == "没有引擎，不能打分，只能自己两边下")
        model.confirmMoves = false
        model.switchMode(to: .solve)
        model.tap(e2)
        await model.waitUntilIdle()
        #expect(model.position.toPlay == .white)
        #expect(model.message == nil)
    }

    @Test("题目类型的说明跟着谁先下换颜色")
    func goalExplanation() {
        #expect(ProblemGoal.capture.explanation(player: .black) == "外面都算白棋：白子跑到外面就逃掉了，黑子跑不出去，要在里面做活。")
        #expect(ProblemGoal.capture.explanation(player: .white).hasPrefix("外面都算黑棋"))
        #expect(ProblemGoal.escape.explanation(player: .black).hasPrefix("外面都算黑棋"))
        #expect(ProblemGoal.allCases.map(\.name) == ["对杀、连接、切断", "吃子、做活", "逃子、杀棋"])
    }
}

/// 有引擎时，摆题页上写明用的是哪个引擎，家长能看出 KataGo 在 GPU 还是 CPU 上跑。
@MainActor
@Suite("打分引擎")
struct EngineJudgingTests {
    private struct NamedEngine: GoEngine {
        let name = "KataGo（CPU）"
        func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis { throw .unavailable("测试") }
    }

    @Test("打分说明里有引擎的名字；空棋盘不打分")
    func summaryNamesEngine() {
        let model = ProblemEditorModel(problem: .sample, engine: NamedEngine())
        #expect(model.canJudge)
        #expect(model.judgeSummary == "打分：KataGo（CPU） 算每一手比最好的下法亏几目")
        let empty = ProblemEditorModel(problem: Problem(), engine: NamedEngine())
        #expect(!empty.canJudge)
        #expect(empty.judgeSummary == "摆好题目后，做题时给每一手打分")
    }

    private func solvingModel(_ problem: Problem = .sample) -> ProblemEditorModel {
        let model = ProblemEditorModel(problem: problem, engine: NamedEngine())
        model.replyDelay = .zero
        model.confirmMoves = false
        model.switchMode(to: .solve)
        return model
    }

    /// 叫停之前一直算不完的假引擎：请求都等着，叫停时以 interrupted 失败。叫停过以后和 SampleEngine 一样马上回答。
    private final class StallingEngine: GoEngine, @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var stalled = true
        private(set) var interrupts = 0
        var pending: Int { lock.withLock { waiting.count } }

        func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis {
            var stopped = false
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let wait = lock.withLock {
                    if stalled { waiting.append(continuation) }
                    return stalled
                }
                if !wait { continuation.resume() } else { stopped = true }
            }
            // 等过的那个请求是被叫停的。
            if stopped { throw .interrupted }
            return try await SampleEngine().analyze(query)
        }

        func interrupt() {
            let all = lock.withLock {
                defer { waiting = []; stalled = false; interrupts += 1 }
                return waiting
            }
            for continuation in all { continuation.resume() }
        }
    }

    @Test("切出 App：正在算的停下、引擎被叫停，不留下“算不出来”；回来以后接着算，和没切出去一样")
    func leaveAndReturn() async {
        let engine = StallingEngine()
        let model = ProblemEditorModel(problem: .sample, engine: engine)
        model.replyDelay = .zero
        model.confirmMoves = false
        model.switchMode(to: .solve)
        model.tap(Point(4, 17))
        #expect(model.isThinking)
        while engine.pending == 0 { await Task.yield() }

        model.leaveForeground()
        #expect(!model.isThinking)
        #expect(engine.interrupts == 1)
        #expect(model.message == nil)
        #expect(model.tree.path.count == 2, "白棋还没应")
        await model.waitUntilIdle()

        model.returnToForeground()
        #expect(model.isThinking)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "黑 E2：0 目。白棋应在 F1", tone: .success))
        #expect(model.tree.path.count == 3)
    }

    @Test("下到题目外面：不打分、提示可以悔棋，对方不应，后面自由下；悔掉再下又接着打分")
    func outsideArea() async {
        let model = solvingModel()
        model.tap(Point(0, 0))
        await model.waitUntilIdle()
        #expect(model.message?.text == "下到题目外面了，可以悔棋再试")
        #expect(model.message?.tone == .warning)
        #expect(model.tree.path.count == 2)
        #expect(!model.isThinking)

        // 后面不打分：白子直接摆上，不会问引擎、不会出"算不出来"。
        model.tap(Point(1, 0))
        await model.waitUntilIdle()
        #expect(model.tree.path.count == 3)
        #expect(model.position.toPlay == .black)
        #expect(model.message == nil)

        model.undo()
        model.undo()
        model.tap(Point(4, 17))
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "这一手算不出来，可以接着下", tone: .info))   // 假引擎一算就报错，说明又在打分了
    }

    @Test("对杀题区域比印出来的图小：图里离棋子太远的地方，提示太远了")
    func insidePrintedButFar() async {
        var problem = Problem.sample
        problem.region = BoardRegion(minX: 0, minY: 9, maxX: 9, maxY: 18)
        let model = solvingModel(problem)
        model.tap(Point(0, 10))
        await model.waitUntilIdle()
        #expect(model.message?.text == "离题目里的棋子太远了，可以悔棋再试")
    }

    /// 每次算 0.4 秒的假引擎：开头黑棋领先 10 目、最想下 E2；别的局面都是白棋最想下 F1。记下每个请求。
    private final class SlowEngine: GoEngine, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [EngineQuery] = []
        var queries: [EngineQuery] { lock.withLock { recorded } }

        func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis {
            lock.withLock { recorded.append(query) }
            try? await Task.sleep(for: .milliseconds(400))
            let best = query.moves.isEmpty ? Point(4, 17) : Point(5, 18)
            let score: Double = query.moves.isEmpty ? 10 : -10
            return EngineAnalysis(candidates: [.init(move: best, visits: 100, winrate: 0.5, scoreLead: score)], winrate: 0.5, scoreLead: score, ownership: [])
        }
    }

    @Test("对方应手前的停顿和引擎计算同时进行，不是算完再停")
    func pauseOverlapsThinking() async throws {
        let model = ProblemEditorModel(problem: .sample, engine: SlowEngine())
        model.replyDelay = .milliseconds(500)
        model.confirmMoves = false
        model.switchMode(to: .solve)
        try await Task.sleep(for: .seconds(1))   // 开头的局面先算好

        let start = ContinuousClock.now
        model.tap(Point(3, 17))   // D2 没被猜到，要现算 0.4 秒
        await model.waitUntilIdle()
        let elapsed = ContinuousClock.now - start
        #expect(model.tree.path.count == 3)
        #expect(elapsed >= .milliseconds(500))
        #expect(elapsed < .milliseconds(800))   // 以前是 0.4 + 0.5 = 0.9 秒
    }

    @Test("思考深度：新开的题按选的档位算，中途改了从下一手开始用")
    func depth() async throws {
        let engine = SlowEngine()
        let model = ProblemEditorModel(problem: .sample, engine: engine)
        model.replyDelay = .zero
        model.confirmMoves = false
        model.engineDepth = .quick
        model.switchMode(to: .solve)
        #expect(model.hasEngine)
        try await Task.sleep(for: .milliseconds(100))
        #expect(engine.queries.first { $0.moves.isEmpty }?.maxVisits == EngineDepth.quick.visits)

        model.engineDepth = .deep
        try await Task.sleep(for: .milliseconds(100))
        model.tap(Point(3, 17))
        await model.waitUntilIdle()
        #expect(engine.queries.first { $0.moves == [Point(3, 17)] }?.maxVisits == EngineDepth.deep.visits)
    }

    /// 按手顺回答的假引擎：开头黑最想下 E2；黑 E2 以后白最想下 D2；黑 E2、白 D2 以后黑最想下 C2；
    /// 再往后白只想停一手。分数都从轮到下的一方看，没人吃亏。
    private struct OtherSideEngine: GoEngine {
        func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis {
            let e2 = Point(4, 17), d2 = Point(3, 17), c2 = Point(2, 17)
            let best: Point? = switch query.moves {
            case []: e2
            case [e2]: d2
            case [e2, d2]: c2
            default: nil
            }
            let score: Double = query.toPlay == .black ? 5 : -5
            return EngineAnalysis(candidates: [.init(move: best, visits: 100, winrate: 0.5, scoreLead: score)], winrate: 0.5, scoreLead: score, ownership: [])
        }
    }

    @Test("孩子执白：AI 给白那手打分，替黑下，又轮到白；悔棋连 AI 的黑一起退，重做一起回来")
    func childPlaysWhite() async {
        // 关掉 AI 陪下自己下黑 E2、白 D2，再打开：孩子执白。
        let model = ProblemEditorModel(problem: .sample, engine: OtherSideEngine())
        model.replyDelay = .zero
        model.confirmMoves = false
        model.switchMode(to: .solve)
        model.autoReply = false
        model.tap(Point(4, 17))
        await model.waitUntilIdle()
        model.tap(Point(3, 17))
        await model.waitUntilIdle()
        model.autoReply = true
        await model.waitUntilIdle()

        #expect(model.message?.text == "白 D2：0 目。黑棋应在 C2")
        #expect(model.tree.path.count == 4)
        #expect(model.lastMove == Point(2, 17))
        #expect(model.position.toPlay == .white)

        model.undo()
        #expect(model.tree.path.count == 2)
        #expect(model.position.toPlay == .white)
        model.redo()
        #expect(model.tree.path.count == 4)
        #expect(model.position.toPlay == .white)
    }
}
