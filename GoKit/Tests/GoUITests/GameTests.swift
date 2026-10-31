import GoCore
import Testing
@testable import GoUI

/// 对弈用的假引擎：最想下的是 E5、C7、G3、C3、G7 里第一个还空着的点（都停一手时 passes 为 true）；
/// 下在 A9 亏 3 目，别的都不亏。A9 上的子归黑方，数子时是白的死子。
struct GameEngine: GoEngine {
    var passes = false

    func analyze(_ query: EngineQuery) async throws(EngineError) -> EngineAnalysis {
        let a9 = Point(0, 0)
        let order = [Point(4, 4), Point(2, 2), Point(6, 6), Point(2, 6), Point(6, 2)]
        let best = passes ? nil : order.first { !query.moves.contains($0) }
        // 从轮到下的一方看：上一手下在 A9，轮到的这一方就白赚 3 目。
        let score: Double = query.moves.last == a9 ? 3 : 0
        var ownership = [Double](repeating: 0, count: 81)
        ownership[0] = query.toPlay == .black ? 0.9 : -0.9
        return EngineAnalysis(candidates: [.init(move: best, visits: 100, winrate: 0.5, scoreLead: score)], winrate: 0.5, scoreLead: score, ownership: ownership)
    }
}

/// 对弈：空棋盘开始，AI 按设置执一方，每手打分，按按钮数子。
@MainActor
@Suite("对弈")
struct GameTests {
    private let a9 = Point(0, 0)
    private let e5 = Point(4, 4)
    private let c7 = Point(2, 2)

    private func gameModel(engine: (any GoEngine)? = GameEngine(), as color: Stone = .black) -> ProblemEditorModel {
        let model = ProblemEditorModel(problem: .sample, engine: engine)
        model.replyDelay = .zero
        model.confirmMoves = false
        model.humanColor = color
        model.switchMode(to: .play)
        return model
    }

    @Test("点“对弈”从 9 路空棋盘开始，黑先，全盘显示，不显示题目的字")
    func startsEmpty() {
        let model = gameModel()
        #expect(model.position.board == Board(size: 9))
        #expect(model.position.toPlay == .black)
        #expect(model.region == .full(size: 9))
        #expect(model.displayedLabels.isEmpty)
        #expect(model.canJudge)
        #expect(model.humanColor == .black)
    }

    @Test("对弈不动摆题里的题目；切回做题还是原来那道题")
    func leavesProblemAlone() async {
        let model = gameModel()
        model.tap(e5)
        await model.waitUntilIdle()
        model.switchMode(to: .setup)
        #expect(model.problem == .sample)
        #expect(model.displayedBoard == Problem.sample.setup)
        model.switchMode(to: .solve)
        #expect(model.position == Problem.sample.startPosition)
    }

    @Test("切到别的模式再回来，这盘原样还在：棋子、悔棋、分数、数子结果都在")
    func keepsGameAcrossModes() async {
        let model = gameModel()
        model.tap(a9)
        await model.waitUntilIdle()
        let board = model.position.board
        let note = model.message
        model.switchMode(to: .solve)
        model.switchMode(to: .play)
        #expect(model.position.board == board)
        #expect(model.message == note)
        #expect(model.canUndo)
        model.undo()
        #expect(model.position.board.isEmpty)
        model.redo()
        #expect(model.message == note, "分数还在，不重新算")

        model.endAndCount()
        await model.waitUntilIdle()
        let counted = model.message
        let count = model.gameCount
        model.switchMode(to: .setup)
        model.switchMode(to: .play)
        #expect(model.message == counted)
        #expect(count != nil)
        #expect(model.gameCount == count)
    }

    @Test("AI 正在想时切走，回来接着想")
    func resumesAfterLeavingWhileThinking() async {
        let model = gameModel()
        model.tap(e5)
        #expect(model.isThinking)
        model.switchMode(to: .setup)
        #expect(!model.isThinking)
        model.switchMode(to: .play)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "👍 黑 E5：0 目。白棋应在 C7", tone: .success))
        #expect(model.lastMove == c7)
    }

    @Test("换棋盘马上生效：还没下子直接换，下了子先确认，取消就不换")
    func boardSizeAppliesNow() async {
        let model = gameModel()
        model.requestGameSize(13)
        #expect(model.pendingGameSize == nil)
        #expect(model.position.board == Board(size: 13))
        #expect(model.region == .full(size: 13))

        model.tap(e5)
        await model.waitUntilIdle()
        model.requestGameSize(19)
        #expect(model.pendingGameSize == 19)
        #expect(model.position.board.size == 13, "确认以前不换")
        model.pendingGameSize = nil
        #expect(model.gameSize == 13)
        model.requestGameSize(19)
        model.changeGameSize(to: 19)
        #expect(model.position.board == Board(size: 19))
    }

    @Test("换边马上生效，这盘接着下；换完轮到 AI，AI 马上下")
    func swapSides() async {
        let model = gameModel()
        model.tap(e5)
        await model.waitUntilIdle()
        #expect(model.position.toPlay == .black)
        model.humanColor = .white
        await model.waitUntilIdle()
        #expect(model.tree.path.count == 4, "棋盘没清，AI 替黑接着下了一手")
        #expect(model.lastMove == Point(6, 6))
        #expect(model.position.toPlay == .white)
    }

    @Test("“新的一盘”从空棋盘重新开始；下了子以后先确认")
    func newGameConfirms() async {
        let model = gameModel()
        model.requestNewGame()
        #expect(!model.isConfirmingNewGame, "还没下子，不用确认")
        model.tap(e5)
        await model.waitUntilIdle()
        model.requestNewGame()
        #expect(model.isConfirmingNewGame)
        model.newGame()
        #expect(!model.isConfirmingNewGame)
        #expect(model.position.board.isEmpty)
        model.switchMode(to: .setup)
        model.switchMode(to: .play)
        #expect(model.position.board.isEmpty)
    }

    @Test("执白时 AI 先下，AI 这一手不打分")
    func aiPlaysFirstAsBlack() async {
        let model = gameModel(as: .white)
        await model.waitUntilIdle()
        #expect(model.lastMove == e5)
        #expect(model.position.toPlay == .white)
        #expect(model.message == EditorMessage(text: "黑棋应在 E5", tone: .info))
        #expect(!model.canUndo, "AI 先下的第一手退不掉")
    }

    @Test("每一手按整个棋盘打分，AI 接着应")
    func scoresWholeBoard() async {
        let model = gameModel()
        model.tap(a9)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "🙂 黑 A9：−3 目。白棋应在 E5", tone: .warning))
        model.tap(c7)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "👍 黑 C7：0 目。白棋应在 G3", tone: .success))
    }

    @Test("关掉 AI 陪下就是两个人轮流下，两边都打分")
    func twoPlayers() async {
        let model = gameModel()
        model.autoReply = false
        model.tap(e5)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "👍 黑 E5：0 目", tone: .success))
        model.tap(c7)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "👍 白 C7：0 目", tone: .success))
        #expect(model.position.toPlay == .black)
    }

    @Test("AI 觉得下完了就停一手，提醒可以数子")
    func aiPasses() async {
        let model = gameModel(engine: GameEngine(passes: true))
        model.tap(e5)
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "👍 黑 E5：0 目。白棋停一手，觉得没地方下了。可以点“结束，数子”", tone: .success))
        #expect(model.lastMove == nil)
        #expect(model.position.toPlay == .black)
    }

    @Test("悔棋连同 AI 的应手一起退，回到自己下的回合")
    func undoToOwnTurn() async {
        let model = gameModel(as: .white)
        await model.waitUntilIdle()
        model.tap(a9)
        await model.waitUntilIdle()
        #expect(model.tree.path.count == 4)
        model.undo()
        #expect(model.tree.path.count == 2)
        #expect(model.position.toPlay == .white)
        #expect(!model.canUndo)
    }

    @Test("数子：引擎判出的死子算给对方，棋盘上标出每个点归谁")
    func countWithEngine() async {
        let model = gameModel()
        model.autoReply = false
        model.tap(e5)
        await model.waitUntilIdle()
        model.tap(a9)
        await model.waitUntilIdle()
        model.endAndCount()
        await model.waitUntilIdle()
        #expect(model.message == EditorMessage(text: "数子：黑 81，白 0，白贴 7.5，黑胜 73.5 目", tone: .info))
        #expect(model.territory.count == 80, "空点和死子都标，活子不标")
        #expect(model.territory[a9] == .black)
        #expect(model.territory[e5] == nil)
    }

    @Test("没有引擎时不判死子，棋盘上的子都算活的")
    func countWithoutEngine() {
        let model = gameModel(engine: nil)
        model.tap(e5)
        model.tap(a9)
        model.endAndCount()
        #expect(model.message == EditorMessage(text: "数子：黑 1，白 1，白贴 7.5，白胜 7.5 目（没有判死子，死子要先提掉再数）", tone: .info))
        #expect(model.territory.isEmpty, "空地两种颜色都碰到，不归谁")
    }

    @Test("数完接着下或者悔棋，方块消失")
    func countClearsOnMove() async {
        let model = gameModel(engine: nil)
        model.tap(e5)
        model.endAndCount()
        #expect(model.territory.count == 80)
        model.tap(c7)
        #expect(model.gameCount == nil)
        #expect(model.territory.isEmpty)
        model.endAndCount()
        model.undo()
        #expect(model.gameCount == nil)
    }
}
