import CoreGraphics
import GoCore
import GoVision
import Observation

public enum EditorMode: String, CaseIterable, Identifiable, Sendable {
    /// 自由摆放棋子，不管规则。
    case setup
    /// 从摆好的局面开始按规则轮流下。
    case solve

    public var id: Self { self }

    public var name: String {
        switch self {
        case .setup: "摆题"
        case .solve: "做题"
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

/// 判题在自己的 actor 里跑，搜索时不卡界面。
/// 有引擎（KataGo）时用引擎，什么题型都能判；没有时用入门判题器，只会吃子、逃子、对杀。
actor Judge {
    private enum Backend {
        case engine(EngineSolver)
        case search(ProblemSolver)
    }

    private let backend: Backend
    /// 判错以后还能不能接着陪下、接着判。引擎看的是眼前的局面，可以；
    /// 入门判题器是按题目开头定的"谁要吃谁"算的，局面一乱就不准，判错就停。
    nonisolated let continuesAfterWrong: Bool

    init?(problem: Problem, engine: (any GoEngine)?) {
        if let engine, !problem.setup.isEmpty {
            backend = .engine(EngineSolver(problem: problem, engine: engine))
            continuesAfterWrong = true
        } else if let solver = ProblemSolver(problem: problem) {
            backend = .search(solver)
            continuesAfterWrong = false
        } else {
            return nil
        }
    }

    /// moves 是从题目开始下的每一手，position 是下完这些以后的局面。
    func judge(_ moves: [Point?], _ position: Position) async -> Verdict {
        switch backend {
        case .engine(let solver): await solver.judge(moves)
        case .search(let solver): solver.judge(position)
        }
    }

    func reply(_ moves: [Point?], _ position: Position) async -> Point? {
        switch backend {
        case .engine(let solver): await solver.reply(moves)
        case .search(let solver): solver.reply(in: position)
        }
    }

    /// 还没提掉、要孩子吃的对方子有几个。入门判题器不知道，返回 0。
    func targetsRemaining(_ moves: [Point?]) async -> Int {
        if case .engine(let solver) = backend { return await solver.targetsRemaining(moves) }
        return 0
    }

    /// 轮到孩子下时先让引擎算着，孩子下完就能马上判。
    func prepare(_ moves: [Point?]) async {
        if case .engine(let solver) = backend { await solver.prepare(moves) }
    }
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
    /// AI 陪下：做题时判孩子每一手的对错，并替对方应。随时可以开关：
    /// 关掉以后孩子自己两边下；再打开，AI 从眼前的局面接着陪下。
    public var autoJudge = true {
        didSet {
            guard autoJudge != oldValue, mode == .solve else { return }
            if autoJudge {
                resumeJudging()
            } else {
                cancelWork()
            }
        }
    }
    /// 孩子下完到对方应手之间停一下，让孩子先看清自己那手。
    public var replyDelay: Duration = .milliseconds(500)

    public private(set) var tree: GameTree
    public private(set) var pending: Point?
    public private(set) var message: EditorMessage?
    /// 正在判题或等对方应手，这时不接受落子和悔棋。
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

    private var nextAlternateStone: Stone = .black
    private let engine: (any GoEngine)?
    private var judge: Judge?
    private var verdicts: [Int: Verdict] = [:]
    private var notes: [Int: EditorMessage] = [:]
    private var work: Task<Void, Never>?

    /// engine 为 nil 时只用入门判题器。
    public init(problem: Problem = .sample, engine: (any GoEngine)? = nil) {
        self.problem = problem
        self.engine = engine
        tree = GameTree(root: problem.startPosition)
    }

    // MARK: - 显示

    public var position: Position { tree.position }
    public var lastMove: Point? { mode == .solve ? tree.lastMove : nil }

    public var displayedBoard: Board { mode == .setup ? problem.setup : position.board }

    /// 从照片识别的题按作业纸上印的那一块显示；手摆的题摆题时显示全盘，做题时只显示棋子所在的局部。
    public var region: BoardRegion {
        if showWholeBoard { return .full(size: problem.setup.size) }
        if let region = problem.region { return region }
        return mode == .setup ? .full(size: problem.setup.size) : .fitting(problem.setup)
    }

    /// 题目印的字只在原来那颗子还在时显示；做题时，试过几种下法的地方标上 A、B……
    public var displayedLabels: [Point: String] {
        let board = displayedBoard
        var labels = problem.labels.filter { board[$0.key] == problem.setup[$0.key] }
        guard mode == .solve else { return labels }
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
        guard mode == .solve, let pending else { return nil }
        return GhostStone(point: pending, stone: position.toPlay)
    }

    /// 摆题时没有气的子，界面用红圈标出来。
    public var stonesWithoutLiberties: Set<Point> {
        Set(problem.setup.groupsWithoutLiberties.flatMap { $0 })
    }

    public var canUndo: Bool { mode == .solve && !isThinking && tree.canUndo }
    public var canRedo: Bool { mode == .solve && !isThinking && tree.canRedo }

    /// 这道题能不能自动判对错。
    public var canJudge: Bool {
        engine == nil ? Objective.infer(for: problem) != nil : !problem.setup.isEmpty
    }

    /// 告诉家长判题按什么标准，方便检查自动找的目标对不对。
    public var judgeSummary: String {
        if let engine {
            return problem.setup.isEmpty ? "摆好题目后，做题时可以自动判对错" : "判题：\(engine.name) 看每一手比最好的下法亏多少"
        }
        guard let goal = problem.goal else { return "设好题目目标后，做题时可以自动判对错" }
        guard let objective = Objective.infer(for: problem) else {
            switch goal {
            case .connect, .cut, .live, .kill: return "\(goal.name)题暂时不能自动判对错"
            default: return "没找到要\(goal.name)的棋子，暂时不能自动判对错"
            }
        }
        let stones = objective.targets.map { problem.setup.group(at: $0).count }.reduce(0, +)
        switch goal {
        case .escape: return "判题：\(objective.defender.name)棋 \(stones) 子要逃出来"
        default: return "判题：吃掉\(objective.defender.name)棋 \(stones) 子"
        }
    }

    /// 当前这一步可以切换的变化。判题时以做题一方的那一手为准，对方的应手跟着走。
    public var variationChoices: [VariationChoice] {
        guard mode == .solve, let node = branchNode, let parent = tree[node].parent else { return [] }
        let siblings = tree[parent].children
        guard siblings.count >= 2 else { return [] }
        return siblings.enumerated().map { index, id in
            VariationChoice(id: id, label: "变化 \(Self.letter(index))", isCurrent: id == node)
        }
    }

    // MARK: - 操作

    public func switchMode(to newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        if newMode == .solve {
            restart()
        } else {
            cancelWork()
        }
        pending = nil
        message = nil
    }

    public func select(_ newTool: SetupTool) {
        tool = newTool
        if newTool == .alternate { nextAlternateStone = .black }
    }

    public func tap(_ p: Point) {
        switch mode {
        case .setup: edit(p)
        case .solve: play(p)
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

    public func changeBoardSize(to size: Int) {
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
        let page = await Task.detached(priority: .userInitiated) {
            try? PageRecognizer.recognize(image)
        }.value
        isRecognizing = false
        guard let page else {
            message = EditorMessage(text: "照片读不出来，换一张试试", tone: .warning)
            return
        }
        show(page, from: image)
    }

    /// 显示识别结果。和识别分开，方便测试。
    public func show(_ page: RecognizedPage, from image: CGImage) {
        guard !page.diagrams.isEmpty else {
            message = EditorMessage(text: "没找到棋盘图。换个角度、拍正一点再试，或者直接手动摆题", tone: .warning)
            return
        }
        scannedPage = ScannedPage(image: image, page: page)
        if page.diagrams.count == 1 {
            loadDiagram(page.diagrams[0].id)
        } else {
            isChoosingDiagram = true
        }
    }

    /// 把选中的那道题放到棋盘上，进入摆题模式校对。
    public func loadDiagram(_ id: Int) {
        guard let scanned = scannedPage, let diagram = scanned.page.diagrams.first(where: { $0.id == id }) else { return }
        switchMode(to: .setup)
        problem = scanned.page.problem(for: diagram)
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

    /// 判题时，App 替对方下的那手跟着一起退回，回到孩子自己的回合。
    public func undo() {
        guard canUndo else { return }
        tree.undo()
        if isJudgeEnabled, position.toPlay != problem.toPlay, tree.canUndo { tree.undo() }
        afterNavigation()
    }

    public func redo() {
        guard canRedo else { return }
        tree.redo()
        if isJudgeEnabled, position.toPlay != problem.toPlay, tree.canRedo { tree.redo() }
        afterNavigation()
    }

    /// 回到摆好的局面重新做，之前试过的变化都清掉。
    public func restart() {
        cancelWork()
        tree = GameTree(root: problem.startPosition)
        judge = Judge(problem: problem, engine: engine)
        verdicts = [:]
        notes = [:]
        afterNavigation()
        if isJudgeEnabled, let judge { Task { await judge.prepare([]) } }
    }

    public func selectVariation(_ id: Int) {
        guard !isThinking else { return }
        tree.go(to: id)
        if isJudgeEnabled, position.toPlay != problem.toPlay, tree.canRedo { tree.redo() }
        afterNavigation()
    }

    public func deleteCurrentVariation() {
        guard !isThinking, let node = branchNode else { return }
        tree.deleteVariation(node)
        afterNavigation()
    }

    /// 等判题和对方应手做完。测试用。
    public func waitUntilIdle() async {
        await work?.value
    }

    // MARK: - 内部

    private var isJudgeEnabled: Bool { autoJudge && judge != nil }

    /// 路上有一手已经答对（题目做完）或算不出来，后面就是自由下，不再判题。
    /// 答错以后，有引擎时接着陪下、接着判；入门判题器就停。
    private var isJudging: Bool {
        guard isJudgeEnabled, let judge else { return false }
        return !tree.path.contains { id in
            switch verdicts[id] {
            case .solved?, .unknown?: true
            case .wrong?: !judge.continuesAfterWrong
            case .correct?, nil: false
            }
        }
    }

    /// 刚打开 AI 陪下：轮到对方、孩子刚下的那手还没判，就先判再应；轮到孩子就先替下一手算着。
    private func resumeJudging() {
        guard isJudging, !isThinking, let judge else { return }
        let node = tree.currentID
        if tree[node].parent != nil, tree.mover(of: node) == problem.toPlay, verdicts[node] == nil {
            startJudging(node)
        } else if position.toPlay == problem.toPlay {
            let next = moves
            Task { await judge.prepare(next) }
        }
    }

    /// 判题时，当前是对方的应手就退到孩子下的那一手。
    private var branchNode: Int? {
        var id = tree.currentID
        if isJudgeEnabled, tree.mover(of: id) != problem.toPlay, let parent = tree[id].parent {
            id = parent
        }
        return tree[id].parent == nil ? nil : id
    }

    private static func letter(_ index: Int) -> String {
        let letters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")
        return index < letters.count ? String(letters[index]) : String(index + 1)
    }

    private func afterNavigation() {
        pending = nil
        message = notes[tree.currentID]
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

        let judging = isJudging && position.toPlay == problem.toPlay
        do throws(MoveError) {
            let result = try tree.play(p)
            let node = tree.currentID
            if let verdict = verdicts[node] {
                // 这一手以前判过：直接走进当时的变化，对方的应手也跟着出来。
                if isJudgeEnabled, verdict == .correct || verdict == .wrong, tree.canRedo { tree.redo() }
                afterNavigation()
            } else if judging {
                startJudging(node)
            } else {
                let note = result.captured.isEmpty ? nil : EditorMessage(text: "提掉 \(result.captured.count) 个子", tone: .info)
                notes[node] = note
                message = note
            }
        } catch {
            message = EditorMessage(text: error.message, tone: .warning)
        }
    }

    private func startJudging(_ node: Int) {
        guard let judge else { return }
        isThinking = true
        message = nil
        let position = tree.position
        let moves = self.moves
        let delay = replyDelay
        let player = problem.toPlay
        let opponent = player.opponent.name

        work = Task {
            let verdict = await judge.judge(moves, position)
            guard !Task.isCancelled, tree.currentID == node else { return }
            verdicts[node] = verdict

            switch verdict {
            case .solved:
                let captured = position.captures(by: player) - problem.startPosition.captures(by: player)
                finish(node, EditorMessage(text: solvedText(captured: captured), tone: .success))
            case .unknown:
                finish(node, EditorMessage(text: "这一手太复杂，算不出来，可以自己接着下", tone: .info))
            case .correct, .wrong:
                let reply = await judge.reply(moves, position)
                if delay > .zero { try? await Task.sleep(for: delay) }
                guard !Task.isCancelled, tree.currentID == node else { return }
                if let reply {
                    // 判题器只会从合法的下法里挑。
                    _ = try? tree.play(reply)
                } else {
                    tree.pass()
                }
                let text: String
                if verdict == .correct {
                    if reply != nil {
                        text = "下得好！\(opponent)棋应在这里，接着下"
                    } else if await judge.targetsRemaining(self.moves) > 0 {
                        // 对方认输停一手了，孩子不一定知道接下来要干什么。
                        text = "下得好！\(opponent)棋不应了，把\(opponent)子提掉就算答对"
                    } else {
                        text = "下得好！\(opponent)棋停了一手，接着下"
                    }
                    let next = self.moves
                    Task { await judge.prepare(next) }
                } else {
                    let next = judge.continuesAfterWrong ? "可以悔棋再试，也可以接着下" : "悔棋再试试"
                    text = reply == nil ? "不对哦，\(opponent)棋不用应也没事。\(next)" : "不对哦，看\(opponent)棋这样应。\(next)"
                }
                let note = EditorMessage(text: text, tone: verdict == .correct ? .success : .warning)
                notes[node] = note
                finish(tree.currentID, note)
            }
        }
    }

    /// 从题目开始到现在下的每一手，nil 是停一手。
    private var moves: [Point?] {
        tree.path.compactMap { tree[$0].move }.map(\.point)
    }

    private func solvedText(captured: Int) -> String {
        let me = problem.toPlay.name
        let opponent = problem.toPlay.opponent.name
        let capturedText = "吃掉了 \(captured) 个\(opponent)子"
        switch problem.goal {
        case .escape: return "答对了！\(me)棋逃出来了"
        case .live: return "答对了！\(me)棋活了"
        case .kill: return "答对了！\(opponent)棋死了"
        case .connect: return "答对了！\(me)棋连上了"
        case .cut: return "答对了！\(opponent)棋被切断了"
        case .capture: return captured > 0 ? "答对了！\(capturedText)" : "答对了！\(opponent)子逃不掉了"
        case .capturingRace: return captured > 0 ? "答对了！\(capturedText)" : "答对了！对杀赢了"
        case nil: return captured > 0 ? "答对了！\(capturedText)" : "答对了！"
        }
    }

    private func finish(_ node: Int, _ note: EditorMessage) {
        notes[node] = note
        message = note
        isThinking = false
    }
}
