import GoCore
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

    public var id: Self { self }

    public var name: String {
        switch self {
        case .black: "黑子"
        case .white: "白子"
        case .alternate: "黑白交替"
        case .erase: "橡皮"
        }
    }
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
actor Judge {
    private let solver: ProblemSolver

    init?(problem: Problem) {
        guard let solver = ProblemSolver(problem: problem) else { return nil }
        self.solver = solver
    }

    func judge(_ position: Position) -> Verdict { solver.judge(position) }
    func reply(in position: Position) -> Point? { solver.reply(in: position) }
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
    /// 题型支持时，做题自动判对错，并替对方应。
    public var autoJudge = true
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

    private var nextAlternateStone: Stone = .black
    private var judge: Judge?
    private var verdicts: [Int: Verdict] = [:]
    private var notes: [Int: EditorMessage] = [:]
    private var work: Task<Void, Never>?

    public init(problem: Problem = .sample) {
        self.problem = problem
        tree = GameTree(root: problem.startPosition)
    }

    // MARK: - 显示

    public var position: Position { tree.position }
    public var lastMove: Point? { mode == .solve ? tree.lastMove : nil }

    public var displayedBoard: Board { mode == .setup ? problem.setup : position.board }

    /// 摆题时显示全盘，方便往任何地方放子；做题时默认只显示题目所在的局部。
    public var region: BoardRegion {
        if mode == .setup || showWholeBoard { return .full(size: problem.setup.size) }
        return .fitting(problem.setup)
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
    public var canJudge: Bool { Objective.infer(for: problem) != nil }

    /// 告诉家长判题按什么标准，方便检查自动找的目标对不对。
    public var judgeSummary: String {
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
        pendingBoardSize = nil
        message = nil
    }

    public func clearBoard() {
        changeBoardSize(to: problem.setup.size)
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
        judge = Judge(problem: problem)
        verdicts = [:]
        notes = [:]
        afterNavigation()
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

    /// 路上有一手已经判完（答对、答错或算不出来），后面就是自由下，不再判题。
    private var isJudging: Bool {
        isJudgeEnabled && !tree.path.contains { id in
            if let verdict = verdicts[id] { return verdict != .correct }
            return false
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
        }
        problem.labels[p] = nil
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
        let delay = replyDelay
        let player = problem.toPlay
        let opponent = player.opponent.name
        let goal = problem.goal

        work = Task {
            let verdict = await judge.judge(position)
            guard !Task.isCancelled, tree.currentID == node else { return }
            verdicts[node] = verdict

            switch verdict {
            case .solved:
                let captured = position.captures(by: player) - problem.startPosition.captures(by: player)
                let text = goal == .escape ? "答对了！\(player.name)棋逃出来了" : "答对了！吃掉了 \(captured) 个\(opponent)子"
                finish(node, EditorMessage(text: text, tone: .success))
            case .unknown:
                finish(node, EditorMessage(text: "这一手太复杂，算不出来，可以自己接着下", tone: .info))
            case .correct, .wrong:
                let reply = await judge.reply(in: position)
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
                    text = reply == nil ? "下得好！\(opponent)棋停了一手，接着下" : "下得好！\(opponent)棋应在这里，接着下"
                } else {
                    text = reply == nil ? "不对哦，\(opponent)棋不用应也没事。悔棋再试试" : "不对哦，看\(opponent)棋这样应。悔棋再试试"
                }
                let note = EditorMessage(text: text, tone: verdict == .correct ? .success : .warning)
                notes[node] = note
                finish(tree.currentID, note)
            }
        }
    }

    private func finish(_ node: Int, _ note: EditorMessage) {
        notes[node] = note
        message = note
        isThinking = false
    }
}
