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

/// 用第 7 题检查做题时的自动判题：正解 E2，D2 会被白棋破解。
@MainActor
@Suite("做题判对错")
struct JudgingTests {
    private let e2 = Point(4, 17)
    private let d2 = Point(3, 17)

    private func solvingModel() -> ProblemEditorModel {
        let model = ProblemEditorModel(problem: .sample, engine: SampleEngine())
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

    @Test("下错了：提示不对，白棋应出破解的一手，接着陪下")
    func wrongMove() async {
        let model = solvingModel()
        model.tap(d2)
        await model.waitUntilIdle()
        #expect(model.message?.tone == .warning)
        #expect(model.message?.text == "不对哦，看白棋这样应。可以悔棋再试，也可以接着下")
        #expect(model.lastMove == e2)
        #expect(model.position.toPlay == .black)

        // 接着下也照样判。假引擎看后面的局面都定了，这一手就算答对。
        model.tap(Point(1, 17))
        await model.waitUntilIdle()
        #expect(model.message?.text == "答对了！")
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

    @Test("没有判题引擎：不判，AI 陪下用不了，自己两边下")
    func withoutEngine() async {
        let model = ProblemEditorModel(problem: .sample)
        #expect(!model.canJudge)
        #expect(!model.hasEngine)
        #expect(model.judgeSummary == "没有判题引擎，只能自己两边下")
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
@Suite("判题引擎")
struct EngineJudgingTests {
    private struct NamedEngine: GoEngine {
        let name = "KataGo（CPU）"
        func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis { throw .unavailable("测试") }
    }

    @Test("判题说明里有引擎的名字；空棋盘不判")
    func summaryNamesEngine() {
        let model = ProblemEditorModel(problem: .sample, engine: NamedEngine())
        #expect(model.canJudge)
        #expect(model.judgeSummary.contains("KataGo（CPU）"))
        #expect(!ProblemEditorModel(problem: Problem(), engine: NamedEngine()).canJudge)
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

    /// 按手顺回答的假引擎：开头黑最想下 E2；黑 E2、白 D2 以后黑最想下 C2；再往后白最想下 B2，
    /// decided 为 true 时白只想停一手（黑的目标达成了）。分数都从轮到下的一方看，没人吃亏。
    private struct OtherSideEngine: GoEngine {
        var decided = false
        func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis {
            let e2 = Point(4, 17), d2 = Point(3, 17), c2 = Point(2, 17)
            let best: Point? = switch query.moves {
            case []: e2
            case [e2]: d2
            case [e2, d2]: c2
            case [e2, d2, c2]: decided ? nil : Point(1, 17)
            default: nil
            }
            let score: Double = query.toPlay == .black ? 5 : -5
            return EngineAnalysis(candidates: [.init(move: best, visits: 100, winrate: 0.5, scoreLead: score)], winrate: 0.5, scoreLead: score, ownership: [])
        }
    }

    /// 关掉 AI 陪下自己下黑 E2、白 D2，再打开：孩子执白。
    private func playingWhite(decided: Bool = false) async -> ProblemEditorModel {
        let model = ProblemEditorModel(problem: .sample, engine: OtherSideEngine(decided: decided))
        model.replyDelay = .zero
        model.confirmMoves = false
        model.switchMode(to: .solve)
        model.autoJudge = false
        model.tap(Point(4, 17))
        model.tap(Point(3, 17))
        model.autoJudge = true
        await model.waitUntilIdle()
        return model
    }

    @Test("孩子执白：AI 判白那手，替黑下，又轮到白；悔棋连 AI 的黑一起退，重做一起回来")
    func childPlaysWhite() async {
        let model = await playingWhite()
        #expect(model.message?.text == "下得好！黑棋应在这里，接着下")
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

    @Test("孩子执白：AI 替黑达成目标，提示结果定了、可以悔棋，后面不再判")
    func opponentReachesGoal() async {
        let model = await playingWhite(decided: true)
        #expect(model.message?.tone == .info)
        #expect(model.message?.text.contains("这题白棋没办法了") == true)
        #expect(model.message?.text.contains("可以悔棋") == true)
        #expect(model.position.toPlay == .white)

        model.tap(Point(1, 17))
        await model.waitUntilIdle()
        #expect(model.tree.path.count == 5)   // 不再替黑下
        #expect(model.position.toPlay == .black)
    }
}
