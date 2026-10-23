import Foundation
import GoCore
import Testing
@testable import GoUI

/// 用第 7 题检查做题时的自动判题：正解 E2，D2 会被白棋破解。
@MainActor
@Suite("做题判对错")
struct JudgingTests {
    private let e2 = Point(4, 17)
    private let d2 = Point(3, 17)

    private func solvingModel() -> ProblemEditorModel {
        let model = ProblemEditorModel(problem: .sample)
        model.replyDelay = .zero
        model.confirmMoves = false
        model.switchMode(to: .solve)
        return model
    }

    @Test("下对了：提示下得好，白棋自动应一手，又轮到黑棋")
    func correctMove() async {
        let model = solvingModel()
        model.tap(e2)
        await model.waitUntilIdle()
        #expect(model.message?.tone == .success)
        #expect(model.tree.path.count == 3)
        #expect(model.position.toPlay == .black)
        #expect(!model.isThinking)
    }

    @Test("下错了：提示不对，白棋应出破解的一手，后面不再判")
    func wrongMove() async {
        let model = solvingModel()
        model.tap(d2)
        await model.waitUntilIdle()
        #expect(model.message?.tone == .warning)
        #expect(model.position.toPlay == .black)

        // 判完以后是自由下：黑白轮流，白棋不再自动应。
        let before = model.tree.path.count
        model.tap(Point(0, 18))
        await model.waitUntilIdle()
        #expect(model.tree.path.count == before + 1)
        #expect(model.position.toPlay == .white)
    }

    @Test("关掉 AI 陪下：自己两边下，白棋不自动应；再打开，AI 先判刚下的那手再应")
    func toggleMidGame() async {
        let model = solvingModel()
        model.autoJudge = false
        model.tap(e2)
        await model.waitUntilIdle()
        #expect(model.tree.path.count == 2)
        #expect(model.position.toPlay == .white)
        #expect(model.message == nil)

        model.autoJudge = true
        await model.waitUntilIdle()
        #expect(model.message?.tone == .success)
        #expect(model.tree.path.count == 3)
        #expect(model.position.toPlay == .black)
    }

    @Test("AI 想的时候关掉开关，就不再应")
    func toggleOffWhileThinking() async {
        let model = solvingModel()
        model.replyDelay = .seconds(5)
        model.tap(e2)
        model.autoJudge = false
        await model.waitUntilIdle()
        #expect(!model.isThinking)
        #expect(model.tree.path.count == 2)
    }

    @Test("悔棋连同白棋的应手一起退回，再下正解还能判")
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

    @Test("试过两种下法后，棋盘上标 A、B，面板上能来回切换")
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
        #expect(model.message?.tone == .warning)
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

    @Test("关掉 AI 陪下后，黑白轮流自由下")
    func freePlayWhenJudgingOff() async {
        let model = solvingModel()
        model.autoJudge = false
        model.tap(d2)
        await model.waitUntilIdle()
        #expect(model.position.toPlay == .white)
        #expect(model.message == nil)
    }

    @Test("摆题时告诉家长判题目标")
    func judgeSummary() {
        let model = ProblemEditorModel(problem: .sample)
        #expect(model.judgeSummary == "判题：吃掉白棋 3 子")
        model.problem.goal = .live
        #expect(model.judgeSummary == "做活题暂时不能自动判对错")
        #expect(!model.canJudge)
    }
}

/// 有引擎时，摆题页上写明用的是哪个引擎，家长能看出 KataGo 在 GPU 还是 CPU 上跑。
@MainActor
@Suite("判题引擎")
struct EngineJudgingTests {
    private struct NamedEngine: GoEngine {
        let name = "KataGo（CPU）"
        func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis { throw .unavailable("测试") }
    }

    @Test("判题说明里有引擎的名字，没设题目目标也能判")
    func summaryNamesEngine() {
        var problem = Problem.sample
        problem.goal = nil
        let model = ProblemEditorModel(problem: problem, engine: NamedEngine())
        #expect(model.canJudge)
        #expect(model.judgeSummary.contains("KataGo（CPU）"))
        #expect(!ProblemEditorModel(problem: problem).canJudge)
    }

    private func solvingModel(_ problem: Problem = .sample) -> ProblemEditorModel {
        let model = ProblemEditorModel(problem: problem, engine: NamedEngine())
        model.replyDelay = .zero
        model.confirmMoves = false
        model.switchMode(to: .solve)
        return model
    }

    @Test("下到题目外面：判错、提示可以悔棋，对方不应，后面自由下；悔掉再下又接着判")
    func outsideArea() async {
        let model = solvingModel()
        model.tap(Point(0, 0))
        await model.waitUntilIdle()
        #expect(model.message?.text == "下到题目外面了，可以悔棋再试")
        #expect(model.message?.tone == .warning)
        #expect(model.tree.path.count == 2)
        #expect(!model.isThinking)

        // 后面不判：白子直接摆上，不会问引擎、不会出"算不出来"。
        model.tap(Point(1, 0))
        await model.waitUntilIdle()
        #expect(model.tree.path.count == 3)
        #expect(model.position.toPlay == .black)
        #expect(model.message == nil)

        model.undo()
        model.undo()
        model.tap(Point(4, 17))
        await model.waitUntilIdle()
        #expect(model.message?.text.contains("算不出来") == true)   // 假引擎一算就报错，说明又在判了
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
}
