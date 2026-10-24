import CoreGraphics
import Foundation
import GoCore
import GoVision
import Observation

public enum EditorMode: String, CaseIterable, Identifiable, Sendable {
    /// 自由摆放棋子，不管规则。
    case setup
    /// 从摆好的局面开始按规则轮流下。
    case solve
    /// 空棋盘开始和 AI 下一整盘，下完数子。
    case play

    public var id: Self { self }

    public var name: String {
        switch self {
        case .setup: "摆题"
        case .solve: "做题"
        case .play: "对弈"
        }
    }
}

public enum SetupTool: String, CaseIterable, Identifiable, Sendable {
    case black
    case white
    case alternate
    case erase
    /// 校对识别结果用：点一下在空、黑、白之间轮换。
    case cycle

    public var id: Self { self }

    public var name: String {
        switch self {
        case .black: "黑子"
        case .white: "白子"
        case .alternate: "黑白交替"
        case .erase: "橡皮"
        case .cycle: "轮换"
        }
    }
}

/// 拍下来的一页作业和识别结果，一页上可能有好几道题。
public struct ScannedPage {
    public let image: CGImage
    public let page: RecognizedPage
    /// 每道题（按 `RecognizedDiagram.id`）在作业本里的 id，选题时点进去的就是作业本里那一道。
    public let problemIDs: [Int: UUID]
    /// 存进作业本的提示，比如“已存进作业本：第 13～18 题”。没有作业本时是 nil。
    public var note: String? = nil
}

extension ScannedPage {
    /// 这道题，id 用存进作业本时的那个。
    func problem(for diagram: RecognizedDiagram) -> Problem {
        var problem = page.problem(for: diagram)
        problem.id = problemIDs[diagram.id] ?? problem.id
        return problem
    }
}

/// 当前这道题和作业本的关系。
public enum SaveState: Sendable {
    case unsaved
    case modified
    case saved
}

/// 给孩子看的提示，语气决定颜色。
public struct EditorMessage: Equatable, Sendable {
    public enum Tone: Sendable {
        case info
        case success
        case warning
    }

    public var text: String
    public var tone: Tone
}

/// 面板上可以切换的一个变化。
public struct VariationChoice: Identifiable, Equatable, Sendable {
    public let id: Int
    /// 和棋盘上标的字母一致，比如"变化 A"。
    public let label: String
    public let isCurrent: Bool
}

/// 打分和替对方应手在自己的 actor 里跑，等引擎时不卡界面。
actor Judge {
    private let solver: EngineSolver
    /// 留给题目的区域，区域外是引擎那边的外框，下在那里引擎不认。
    nonisolated let area: BoardRegion

    /// 没有引擎，或者做题时棋盘是空的，就不用引擎。对弈从空棋盘开始。
    init?(problem: Problem, engine: (any GoEngine)?, depth: EngineDepth, purpose: EngineSolver.Purpose = .problem, strength: AIStrength = .full) {
        guard let engine, purpose == .game || !problem.setup.isEmpty else { return nil }
        solver = EngineSolver(problem: problem, engine: engine, depth: depth, purpose: purpose, strength: strength)
        area = solver.frame.area
    }

    /// moves 是从题目开始下的每一手，给最后一手打分。
    func score(_ moves: [Point?]) async -> MoveScore {
        await solver.score(moves)
    }

    func reply(_ moves: [Point?]) async -> Reply {
        await solver.reply(moves)
    }

    func setDepth(_ depth: EngineDepth) async {
        await solver.setDepth(depth)
    }

    func setStrength(_ strength: AIStrength) async {
        await solver.setStrength(strength)
    }

    func count(_ moves: [Point?]) async -> GameCount? {
        await solver.count(moves)
    }

    /// 轮到人下时先让引擎算着，下完就能马上打分。
    func prepare(_ moves: [Point?]) async {
        await solver.prepare(moves)
    }
}

/// 离开对弈时存下的一盘：变化树和跟着它的打分、提示、哪些手是 AI 下的。
private struct GameSession {
    var tree: GameTree
    var judge: Judge?
    var scores: [Int: MoveScore]
    var aiMoves: Set<Int>
    var notes: [Int: EditorMessage]
    var count: GameCount?
}

/// 摆题和做题的状态。界面只读这里的属性、调这里的方法。
@MainActor
@Observable
public final class ProblemEditorModel {
    public var problem: Problem
    public private(set) var mode: EditorMode = .setup
    public private(set) var tool: SetupTool = .black
    /// 做题时先点一下显示虚影，再点同一个点才落子，防止孩子误触。
    public var confirmMoves = true
    /// 做题时显示全盘；关闭时只显示题目所在的局部。
    public var showWholeBoard = false
    public var showCoordinates = false
    /// AI 打分：每一手显示比最好的下法亏几目，不说对错，好不好由人看分数决定。
    /// 随时可以开关，和 AI 陪下互不影响；再打开时，最后一手还没打分就补上。
    public var autoScore = true {
        didSet { if autoScore != oldValue { switchesChanged() } }
    }
    /// AI 陪下：替孩子的对手下。随时可以开关：关掉以后孩子自己两边下（照样打分）；
    /// 再打开，AI 从眼前的局面接着应。
    public var autoReply = true {
        didSet { if autoReply != oldValue { switchesChanged() } }
    }
    /// 孩子下完到对方应手至少隔这么久，让孩子先看清自己那手。引擎算的时间也算在里面。
    public var replyDelay: Duration = .milliseconds(300)
    /// 引擎每一步想多深。改了从下一手开始用。
    public var engineDepth: EngineDepth = .standard {
        didSet {
            guard engineDepth != oldValue, let judge else { return }
            let depth = engineDepth
            Task { await judge.setDepth(depth) }
        }
    }
    /// 这一盘对弈用几路棋盘。换大小就是开新的一盘，用 requestGameSize 换。
    public private(set) var gameSize = 9
    /// 等用户确认要换成的对弈棋盘大小。不为 nil 时界面弹出确认框。
    public var pendingGameSize: Int?
    /// 对弈时人执的颜色。中途改就是换边，这盘接着下；换完轮到 AI，AI 马上下。
    public var humanColor: Stone = .black {
        didSet { if humanColor != oldValue { switchesChanged() } }
    }
    /// 对弈时 AI 让多少。改了从 AI 的下一手开始用。
    public var aiStrength: AIStrength = .beginner {
        didSet {
            guard aiStrength != oldValue, let judge else { return }
            let strength = aiStrength
            Task { await judge.setStrength(strength) }
        }
    }
    /// 点了“结束，数子”的结果。接着下、悔棋就清掉。
    public private(set) var gameCount: GameCount?
    /// 为 true 时界面弹出“重新开始一盘”的确认框。
    public var isConfirmingNewGame = false
    /// 有引擎（KataGo）。没有时不能打分，AI 也不应，只能自己两边下。
    public var hasEngine: Bool { engine != nil }

    public private(set) var tree: GameTree
    public private(set) var pending: Point?
    public private(set) var message: EditorMessage?
    /// 正在打分或等对方应手，这时不接受落子和悔棋。
    public private(set) var isThinking = false

    /// 等用户确认要换成的棋盘大小。不为 nil 时界面弹出确认框。
    public var pendingBoardSize: Int?
    public var isConfirmingClear = false

    /// 最近拍的那页作业。做完一道题可以回来选同一页的下一道。
    public private(set) var scannedPage: ScannedPage?
    /// 正在识别照片。
    public private(set) var isRecognizing = false
    /// 为 true 时界面弹出选题页。
    public var isChoosingDiagram = false
    /// 当前这道题在照片里的样子，校对时对照着看。
    public private(set) var referenceImage: CGImage?
    /// 识别时没认准的点，校对时用橙色圈提醒。改过的点就不再提醒。
    public private(set) var uncertainPoints: Set<Point> = []
    /// 为 true 时界面弹出作业本。
    public var isShowingHomework = false
    /// 没有时不存题，作业本按钮也不显示。
    public let homework: HomeworkStore?

    private var nextAlternateStone: Stone = .black
    /// 这一盘对弈的空棋盘。对弈不动 problem，也不存作业本。
    private var gameProblem = Problem(setup: Board(size: 9))
    /// 离开对弈时存着的那一盘，回来接着下。只在内存里。
    private var savedGame: GameSession?
    private let engine: (any GoEngine)?
    private var judge: Judge?
    private var scores: [Int: MoveScore] = [:]
    /// AI 替孩子的对手下的那些手（落子和停一手）。孩子执哪一方，看最近一手不是 AI 下的棋。
    private var aiMoves: Set<Int> = []
    private var notes: [Int: EditorMessage] = [:]
    private var work: Task<Void, Never>?

    /// engine 为 nil 时不打分，只能自己两边下；homework 为 nil 时不存题。
    public init(problem: Problem = .sample, engine: (any GoEngine)? = nil, homework: HomeworkStore? = nil) {
        self.problem = problem
        self.engine = engine
        self.homework = homework
        tree = GameTree(root: problem.startPosition)
    }

    // MARK: - 显示

    public var position: Position { tree.position }
    public var lastMove: Point? { mode != .setup ? tree.lastMove : nil }

    public var displayedBoard: Board { mode == .setup ? problem.setup : position.board }

    /// 从照片识别的题按作业纸上印的那一块显示；手摆的题摆题时显示全盘，做题时只显示棋子所在的局部。
    public var region: BoardRegion {
        if mode == .play { return .full(size: gameProblem.setup.size) }
        if showWholeBoard { return .full(size: problem.setup.size) }
        if let region = problem.region { return region }
        return mode == .setup ? .full(size: problem.setup.size) : .fitting(problem.setup)
    }

    /// 题目印的字只在原来那颗子还在时显示；做题时，试过几种下法的地方标上 A、B……
    public var displayedLabels: [Point: String] {
        let board = displayedBoard
        var labels = mode == .play ? [:] : problem.labels.filter { board[$0.key] == problem.setup[$0.key] }
        guard mode != .setup else { return labels }
        let children = tree.current.children
        if children.count >= 2 {
            for (index, child) in children.enumerated() {
                if let p = tree[child].move?.point, board[p] == nil {
                    labels[p] = Self.letter(index)
                }
            }
        }
        return labels
    }

    public var ghost: GhostStone? {
        guard mode != .setup, let pending else { return nil }
        return GhostStone(point: pending, stone: position.toPlay)
    }

    /// 摆题时没有气的子，界面用红圈标出来。
    public var stonesWithoutLiberties: Set<Point> {
        Set(problem.setup.groupsWithoutLiberties.flatMap { $0 })
    }

    /// 当前这道题和作业本里的比：没存过、存过但改了、一样。
    public var saveState: SaveState {
        guard let saved = homework?[problem.id] else { return .unsaved }
        return saved.problem == problem ? .saved : .modified
    }

    /// 对弈执白时，AI 先下的第一手退不掉：退了 AI 还得再下。
    public var canUndo: Bool {
        guard mode != .setup, !isThinking, tree.canUndo else { return false }
        return !(mode == .play && isReplyEnabled && aiMoves.contains(tree.currentID) && tree[tree.currentID].parent == GameTree.rootID)
    }
    public var canRedo: Bool { mode != .setup && !isThinking && tree.canRedo }

    /// 这道题（或这一盘）能不能用引擎打分、陪下。对弈从空棋盘开始也能用。
    public var canJudge: Bool { engine != nil && (mode == .play || !problem.setup.isEmpty) }

    /// 对弈时数子的方块：空点和死子归谁。活子上不画。
    public var territory: [Point: Stone] {
        guard mode == .play, let gameCount else { return [:] }
        let board = position.board
        return gameCount.owner.filter { board[$0.key] == nil || gameCount.dead.contains($0.key) }
    }

    /// 告诉家长用什么打分。
    public var judgeSummary: String {
        guard let engine else { return "没有引擎，不能打分，只能自己两边下" }
        return problem.setup.isEmpty ? "摆好题目后，做题时给每一手打分" : "打分：\(engine.name) 算每一手比最好的下法亏几目"
    }

    /// 当前这一步可以切换的变化。AI 陪下时以人下的那一手为准，AI 的应手跟着走。
    public var variationChoices: [VariationChoice] {
        guard mode != .setup, let node = branchNode, let parent = tree[node].parent else { return [] }
        let siblings = tree[parent].children
        guard siblings.count >= 2 else { return [] }
        return siblings.enumerated().map { index, id in
            VariationChoice(id: id, label: "变化 \(Self.letter(index))", isCurrent: id == node)
        }
    }

    // MARK: - 操作

    public func switchMode(to newMode: EditorMode) {
        guard newMode != mode else { return }
        if mode == .play {
            // AI 正在想的那手先停下，回来再接着想。
            cancelWork()
            savedGame = GameSession(tree: tree, judge: judge, scores: scores, aiMoves: aiMoves, notes: notes, count: gameCount)
        }
        mode = newMode
        pending = nil
        message = nil
        switch newMode {
        case .solve:
            // 作业本里有这道题时，校对改过的地方跟着存回去。
            if saveState == .modified { saveProblem() }
            restart()
        case .play:
            if let savedGame { restore(savedGame) } else { newGame() }
        case .setup:
            cancelWork()
            gameCount = nil
        }
    }

    public func select(_ newTool: SetupTool) {
        tool = newTool
        if newTool == .alternate { nextAlternateStone = .black }
    }

    public func tap(_ p: Point) {
        switch mode {
        case .setup: edit(p)
        case .solve, .play: play(p)
        }
    }

    /// 棋盘是空的就直接换大小；有子时先记下来，等用户确认会清空棋子。
    public func requestBoardSize(_ size: Int) {
        guard size != problem.setup.size else { return }
        if problem.setup.isEmpty {
            changeBoardSize(to: size)
        } else {
            pendingBoardSize = size
        }
    }

    /// 清空或换棋盘大小后摆的是另一道题，不再覆盖作业本里原来那道。
    public func changeBoardSize(to size: Int) {
        problem.id = UUID()
        problem.setup = Board(size: size)
        problem.labels = [:]
        problem.region = nil
        uncertainPoints = []
        referenceImage = nil
        pendingBoardSize = nil
        message = nil
    }

    public func clearBoard() {
        changeBoardSize(to: problem.setup.size)
    }

    /// 识别一页作业照片。只有一道题就直接导入，有好几道就弹出选题页。
    public func importPhoto(_ image: CGImage) async {
        isRecognizing = true
        message = nil
        // 先按页面上的字把照片转正，题才能按书上的朝向贴到棋盘上；后面显示、裁原图都用转正后的图。
        let result = await Task.detached(priority: .userInitiated) { () -> (CGImage, RecognizedPage)? in
            let upright = PageOrientation.upright(image)
            guard let page = try? PageRecognizer.recognize(upright) else { return nil }
            return (upright, page)
        }.value
        isRecognizing = false
        guard let (upright, page) = result else {
            message = EditorMessage(text: "照片读不出来，换一张试试", tone: .warning)
            return
        }
        show(page, from: upright)
    }

    /// 显示识别结果。和识别分开，方便测试。
    public func show(_ page: RecognizedPage, from image: CGImage) {
        guard !page.diagrams.isEmpty else {
            message = EditorMessage(text: "没找到棋盘图。换个角度、拍正一点再试，或者直接手动摆题", tone: .warning)
            return
        }
        // 重拍的题：作业本里已经有同一页同一题号的，沿用它的 id 和第一次存的日期，存的时候就是换掉它，不多存一份。
        var ids: [Int: UUID] = [:]
        var earlier: [Int: SavedProblem] = [:]
        for diagram in page.diagrams {
            if let homework, let pageNumber = page.pageNumber, let number = diagram.number,
               let old = homework.photoProblem(page: pageNumber, number: number, title: page.title(for: diagram)),
               !ids.values.contains(old.id) {
                ids[diagram.id] = old.id
                earlier[diagram.id] = old
            } else {
                ids[diagram.id] = UUID()
            }
        }
        var scanned = ScannedPage(image: image, page: page, problemIDs: ids)
        // 拍下来的每道题都存进作业本，以后能再选。
        if let homework {
            let now = Date.now
            for diagram in page.diagrams {
                homework.save(
                    SavedProblem(
                        problem: scanned.problem(for: diagram), saved: earlier[diagram.id]?.saved ?? now, hasPhoto: true,
                        isIncomplete: diagram.isIncomplete, page: page.pageNumber, number: diagram.number
                    ),
                    photo: PhotoLoader.crop(image, to: diagram.bounds)
                )
            }
            scanned.note = Self.importNote(
                numbers: page.diagrams.compactMap(\.number),
                unnumbered: page.diagrams.count { $0.number == nil },
                replaced: page.diagrams.filter { earlier[$0.id] != nil }.compactMap(\.number)
            )
        }
        scannedPage = scanned
        if page.diagrams.count == 1 {
            loadDiagram(page.diagrams[0].id)
            // 直接进了摆题，不经过选题页，存没存作业本写在提示开头。
            if homework != nil, let current = message {
                let prefix = earlier.isEmpty ? "已存进作业本。" : "作业本里原来就有这道题，换成了这次拍的。"
                message = EditorMessage(text: prefix + current.text, tone: current.tone)
            }
        } else {
            isChoosingDiagram = true
        }
    }

    /// 拍完一页的提示：存了哪几道题，哪几道是重拍换掉的。
    static func importNote(numbers: [Int], unnumbered: Int, replaced: [Int]) -> String {
        var text = numbers.isEmpty
            ? "已存进作业本：\(unnumbered) 道题"
            : "已存进作业本：第 \(numberList(numbers)) 题" + (unnumbered > 0 ? "，还有 \(unnumbered) 道没读出题号" : "")
        if !replaced.isEmpty {
            text += "。其中第 \(numberList(replaced)) 题原来就有，换成了这次拍的"
        }
        return text
    }

    /// 三道以上连着的题号写成“13～15”，其余用顿号隔开，比如“13～15、17”。
    static func numberList(_ numbers: [Int]) -> String {
        var runs: [[Int]] = []
        for number in Set(numbers).sorted() {
            if let last = runs.last?.last, number == last + 1 {
                runs[runs.count - 1].append(number)
            } else {
                runs.append([number])
            }
        }
        return runs.flatMap { run in run.count >= 3 ? ["\(run[0])～\(run[run.count - 1])"] : run.map(String.init) }
            .joined(separator: "、")
    }

    /// 把选中的那道题放到棋盘上，进入摆题模式校对。
    public func loadDiagram(_ id: Int) {
        guard let scanned = scannedPage, let diagram = scanned.page.diagrams.first(where: { $0.id == id }) else { return }
        switchMode(to: .setup)
        problem = scanned.problem(for: diagram)
        referenceImage = PhotoLoader.crop(scanned.image, to: diagram.bounds)
        uncertainPoints = Set(diagram.uncertain.map(diagram.boardPoint))
        tool = .cycle
        isChoosingDiagram = false
        if diagram.isIncomplete {
            message = EditorMessage(text: "这道题好像没拍全，缺的部分要照着书补上，或者重拍一张", tone: .warning)
        } else {
            message = EditorMessage(text: "对照原图检查一下棋子，摆错的地方点一下就能改", tone: .info)
        }
    }

    /// 把当前这道题存进作业本，已经存过的覆盖，第一次存的日期和原图不变。
    public func saveProblem() {
        guard let homework else { return }
        if var saved = homework[problem.id] {
            saved.problem = problem
            homework.save(saved)
        } else {
            homework.save(SavedProblem(problem: problem, hasPhoto: referenceImage != nil), photo: referenceImage)
        }
    }

    /// 从作业本里选一道放到棋盘上，和拍照导入一样先进摆题模式，有原图就对照着看。
    public func load(_ saved: SavedProblem) {
        switchMode(to: .setup)
        problem = saved.problem
        referenceImage = homework?.photo(for: saved.id)
        uncertainPoints = []
        isShowingHomework = false
        message = EditorMessage(text: "从作业本里拿出了\(saved.problem.title.isEmpty ? "这道题" : saved.problem.title)，点“做题”开始", tone: .info)
    }

    /// AI 陪下时，AI 替对方下的那手跟着一起退回，回到孩子自己的回合。
    public func undo() {
        guard canUndo else { return }
        let replied = aiMoves.contains(tree.currentID)
        tree.undo()
        if isReplyEnabled, replied, tree.canUndo { tree.undo() }
        afterNavigation()
    }

    public func redo() {
        guard canRedo else { return }
        tree.redo()
        redoReply()
        afterNavigation()
    }

    /// 回到摆好的局面重新做，之前试过的变化都清掉。对弈时是同样设置的一盘新棋。
    public func restart() {
        cancelWork()
        let start = mode == .play ? gameProblem : problem
        tree = GameTree(root: start.startPosition)
        judge = Judge(
            problem: start, engine: engine, depth: engineDepth,
            purpose: mode == .play ? .game : .problem, strength: aiStrength
        )
        scores = [:]
        aiMoves = []
        notes = [:]
        afterNavigation()
        // 对弈执白时 AI 先下；别的情况先替人的第一手算着。
        resume()
    }

    /// 按现在的棋盘大小，从空棋盘开始一盘新的对弈。
    public func newGame() {
        isConfirmingNewGame = false
        savedGame = nil
        gameProblem = Problem(setup: Board(size: gameSize))
        restart()
    }

    /// 已经下了子，先确认，免得误点把这盘弄没了。
    public func requestNewGame() {
        if gameHasMoves {
            isConfirmingNewGame = true
        } else {
            newGame()
        }
    }

    /// 对弈时换棋盘大小：还没下子直接换；下了子先记下来，等用户确认会重新开始一盘。
    public func requestGameSize(_ size: Int) {
        guard size != gameSize else { return }
        if gameHasMoves {
            pendingGameSize = size
        } else {
            changeGameSize(to: size)
        }
    }

    public func changeGameSize(to size: Int) {
        pendingGameSize = nil
        gameSize = size
        newGame()
    }

    /// 结束这一盘，按中国规则数子。有引擎时引擎判死子；没有引擎或者引擎出错，棋盘上的子都算活的。
    public func endAndCount() {
        guard mode == .play, !isThinking else { return }
        pending = nil
        let board = position.board
        let komi = EngineSolver.gameKomi
        guard let judge else {
            show(GameCount(board: board, komi: komi, judgedDead: false))
            return
        }
        let moves = self.moves
        let node = tree.currentID
        isThinking = true
        message = nil
        work = Task {
            let count = await judge.count(moves)
            guard !Task.isCancelled, tree.currentID == node else { return }
            isThinking = false
            show(count ?? GameCount(board: board, komi: komi, judgedDead: false))
        }
    }

    public func selectVariation(_ id: Int) {
        guard !isThinking else { return }
        tree.go(to: id)
        redoReply()
        afterNavigation()
    }

    public func deleteCurrentVariation() {
        guard !isThinking, let node = branchNode else { return }
        tree.deleteVariation(node)
        afterNavigation()
    }

    /// 等打分和对方应手做完。测试用。
    public func waitUntilIdle() async {
        await work?.value
    }

    // MARK: - 内部

    private var isReplyEnabled: Bool { autoReply && judge != nil }

    /// 对弈时 AI 执的颜色。
    private var aiColor: Stone? { mode == .play ? humanColor.opponent : nil }

    /// 这一盘已经下了子（包括 AI 先下的那手）。
    private var gameHasMoves: Bool { !tree[GameTree.rootID].children.isEmpty }

    /// 回到存着的那一盘。离开时家长可能改过思考深度和棋力，按现在的设置接着算。
    private func restore(_ game: GameSession) {
        savedGame = nil
        tree = game.tree
        judge = game.judge
        scores = game.scores
        aiMoves = game.aiMoves
        notes = game.notes
        afterNavigation()
        gameCount = game.count
        if let count = game.count { message = EditorMessage(text: Self.countText(count), tone: .info) }
        if let judge = game.judge {
            let depth = engineDepth, strength = aiStrength
            Task {
                await judge.setDepth(depth)
                await judge.setStrength(strength)
            }
        }
        resume()
    }

    /// 这时要不要用引擎：两个开关至少开一个。没有终点，一直打分、一直应；
    /// 只有一手下到了题目区域外面时停下（引擎那边那里是外框，算不了），悔掉那手才接着来。
    private var isUsingEngine: Bool {
        guard autoScore || autoReply, let judge else { return false }
        return !moves.contains { $0.map { !judge.area.contains($0) } ?? false }
    }

    /// 开关变了：正在做的停下，按新的开关从眼前的局面接着来。
    private func switchesChanged() {
        guard mode != .setup else { return }
        cancelWork()
        resume()
    }

    /// 最后一手是人下的，还缺分数或者缺 AI 的应手，就补上；对弈时轮到 AI 也让它下。否则轮到人下，先替下一手算着。
    private func resume() {
        guard isUsingEngine, !isThinking, let judge else { return }
        let node = tree.currentID
        if needsWork(node) {
            start(node)
        } else {
            let next = moves
            Task { await judge.prepare(next) }
        }
    }

    /// 人下的这一手还缺分数，或者该 AI 下了、还没下。
    private func needsWork(_ node: Int) -> Bool {
        (autoScore && isHumanMove(node) && scores[node] == nil) || needsReply(node)
    }

    /// 这一手是人下的（不是 AI 下的，也不是根节点）。
    private func isHumanMove(_ node: Int) -> Bool {
        tree.mover(of: node) != nil && !aiMoves.contains(node)
    }

    /// AI 陪下开着、该 AI 下了、还没下。做题时人下了 AI 就应；对弈时看轮到的是不是 AI 执的颜色，所以执白时 AI 先下。
    private func needsReply(_ node: Int) -> Bool {
        guard autoReply, !tree[node].children.contains(where: { aiMoves.contains($0) }) else { return false }
        if let aiColor { return tree[node].position.toPlay == aiColor }
        return isHumanMove(node)
    }

    /// AI 陪下时，当前是 AI 替对手下的那手就退到孩子下的那一手。
    private var branchNode: Int? {
        var id = tree.currentID
        if isReplyEnabled, aiMoves.contains(id), let parent = tree[id].parent {
            id = parent
        }
        return tree[id].parent == nil ? nil : id
    }

    /// 走到孩子下的一手以后，当时 AI 替对手下的那手也跟着走出来。
    private func redoReply() {
        if isReplyEnabled, let next = tree.redoTarget, aiMoves.contains(next) { tree.redo() }
    }

    private static func letter(_ index: Int) -> String {
        let letters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")
        return index < letters.count ? String(letters[index]) : String(index + 1)
    }

    private func afterNavigation() {
        pending = nil
        gameCount = nil
        message = notes[tree.currentID]
    }

    private func show(_ count: GameCount) {
        gameCount = count
        message = EditorMessage(text: Self.countText(count), tone: .info)
    }

    private func cancelWork() {
        work?.cancel()
        work = nil
        isThinking = false
    }

    /// 摆题：点空点放子，点同色子拿掉，点异色子换颜色。
    private func edit(_ p: Point) {
        let current = problem.setup[p]
        switch tool {
        case .black:
            problem.setup[p] = current == .black ? nil : .black
        case .white:
            problem.setup[p] = current == .white ? nil : .white
        case .alternate:
            if current == nil {
                problem.setup[p] = nextAlternateStone
                nextAlternateStone = nextAlternateStone.opponent
            } else {
                problem.setup[p] = nil
            }
        case .erase:
            problem.setup[p] = nil
        case .cycle:
            switch current {
            case nil: problem.setup[p] = .black
            case .black?: problem.setup[p] = .white
            case .white?: problem.setup[p] = nil
            }
        }
        problem.labels[p] = nil
        uncertainPoints.remove(p)
        message = nil
    }

    private func play(_ p: Point) {
        guard !isThinking else { return }
        if confirmMoves && pending != p {
            if position.board[p] != nil {
                pending = nil
                message = EditorMessage(text: MoveError.occupied.message, tone: .warning)
            } else {
                pending = p
                message = nil
            }
            return
        }
        pending = nil

        // 孩子点下去的这一子是哪色，孩子就执哪色，AI 下另一色。
        let using = isUsingEngine
        do throws(MoveError) {
            let result = try tree.play(p)
            gameCount = nil
            let node = tree.currentID
            if aiMoves.remove(node) != nil {
                // 以前 AI 在这里下过同一手，这回是孩子自己下的，当成新的一手。
                scores[node] = nil
                notes[node] = nil
            }
            if using, needsWork(node) {
                start(node)
            } else if using || notes[node] != nil {
                // 这一手以前下过：直接走进当时的变化，分数照旧，AI 的应手也跟着出来。
                redoReply()
                afterNavigation()
            } else {
                let note = result.captured.isEmpty ? nil : EditorMessage(text: "提掉 \(result.captured.count) 个子", tone: .info)
                notes[node] = note
                message = note
            }
        } catch {
            message = EditorMessage(text: error.message, tone: .warning)
        }
    }

    /// 给人刚下的这一手打分（开着 AI 打分、还没打过分时），再替对手应（开着 AI 陪下时）。
    /// 对弈执白时在根节点上调用：不打分，只让 AI 先下。
    private func start(_ node: Int) {
        guard let judge else { return }
        let mover = tree.mover(of: node)
        let moves = self.moves
        let point = tree[node].move?.point
        if let point, !judge.area.contains(point) {
            // 题目区域外引擎那边是外框，算不了：不打分，不替对方应。
            // 对杀题的区域只到棋子外面一路，可能比印出来的图小，这时说"太远了"。
            scores[node] = .outside
            let printed = problem.region?.contains(point) ?? false
            let text = printed ? "离题目里的棋子太远了，可以悔棋再试" : "下到题目外面了，可以悔棋再试"
            finish(node, EditorMessage(text: text, tone: .warning))
            return
        }
        isThinking = true
        message = nil
        let scoring = autoScore && isHumanMove(node) && scores[node] == nil
        let replying = needsReply(node)
        let captured = tree[node].captured.count
        let size = tree.position.board.size
        let delay = replyDelay
        let opponent = tree[node].position.toPlay.name
        let game = mode == .play
        let start = ContinuousClock.now

        work = Task {
            if scoring {
                let score = await judge.score(moves)
                guard !Task.isCancelled, tree.currentID == node else { return }
                scores[node] = score
            }
            let score = autoScore && isHumanMove(node) ? scores[node] : nil
            var replyText: String?
            // 算不出分数时引擎多半也算不出应手，不替对方乱下。
            if replying, score != .unknown {
                let reply = await judge.reply(moves)
                // 引擎算得快，就补足停顿；算得比停顿久，算完马上应。
                let wait = delay - (ContinuousClock.now - start)
                if wait > .zero { try? await Task.sleep(for: wait) }
                guard !Task.isCancelled, tree.currentID == node else { return }
                // 引擎和闲棋都只从合法的下法里挑。
                switch reply {
                case let .play(p):
                    _ = try? tree.play(p)
                    replyText = "\(opponent)棋应在 \(Coordinates.name(of: p, size: size))"
                case let .idle(p):
                    _ = try? tree.play(p)
                    replyText = "\(opponent)棋没什么好下的了，走一步闲棋：\(Coordinates.name(of: p, size: size))"
                case .pass:
                    tree.pass()
                    // 对弈时 AI 觉得下完了才停，提醒可以数子；做题时只有一个能下的点都没有才停。
                    replyText = game
                        ? "\(opponent)棋停一手，觉得没地方下了。可以点“结束，数子”"
                        : "\(opponent)棋没地方下了，停一手"
                }
                aiMoves.insert(tree.currentID)
            }
            let note = Self.note(mover: mover, point: point, size: size, score: score, captured: captured, reply: replyText)
            notes[node] = note
            finish(tree.currentID, note)
            let next = self.moves
            Task { await judge.prepare(next) }
        }
    }

    /// 给人看的一句话：这一手的分数、提了几个子、对方应在哪。不说对错，颜色按分数上。
    static func note(mover: Stone?, point: Point?, size: Int, score: MoveScore?, captured: Int, reply: String?) -> EditorMessage {
        if score == .unknown {
            return EditorMessage(text: "这一手算不出来，可以接着下", tone: .info)
        }
        var parts: [String] = []
        var head = ""
        var tone = EditorMessage.Tone.info
        if case let .loss(loss)? = score, let mover {
            let name = point.map { Coordinates.name(of: $0, size: size) } ?? "停一手"
            head = "\(mover.name) \(name)：\(scoreText(loss))"
            tone = loss <= EngineSolver.tolerance ? .success : .warning
        }
        if captured > 0 {
            head += head.isEmpty ? "提掉 \(captured) 个子" : "，提掉 \(captured) 个子"
        }
        if !head.isEmpty { parts.append(head) }
        if let reply { parts.append(reply) }
        return EditorMessage(text: parts.joined(separator: "。"), tone: tone)
    }

    /// 亏了几目：负数、保留一位小数，比如"−2.3 目"；不到 0.05 目写"0 目"。用减号"−"，比连字符好认。
    static func scoreText(_ loss: Double) -> String {
        let tenths = (loss * 10).rounded()
        guard tenths > 0 else { return "0 目" }
        let text = tenths.truncatingRemainder(dividingBy: 10) == 0 ? String(Int(tenths / 10)) : String(format: "%.1f", tenths / 10)
        return "−\(text) 目"
    }

    /// 数子的结果，比如"数子：黑 45，白 36，白贴 7.5，黑胜 1.5 目"。没判死子时提醒先提掉死子。
    static func countText(_ count: GameCount) -> String {
        let margin = count.margin
        let winner = margin > 0 ? "黑胜" : "白胜"
        var text = "数子：黑 \(count.black)，白 \(count.white)，白贴 \(number(count.komi))，\(winner) \(number(abs(margin))) 目"
        if !count.judgedDead { text += "（没有判死子，死子要先提掉再数）" }
        return text
    }

    /// 整数不写小数点，比如 7.5、2。
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// 从题目开始到现在下的每一手，nil 是停一手。
    private var moves: [Point?] {
        tree.path.compactMap { tree[$0].move }.map(\.point)
    }

    private func finish(_ node: Int, _ note: EditorMessage) {
        notes[node] = note
        message = note
        isThinking = false
    }
}
