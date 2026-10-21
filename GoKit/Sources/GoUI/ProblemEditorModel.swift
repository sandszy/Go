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

    public private(set) var position: Position
    public private(set) var lastMove: Point?
    public private(set) var pending: Point?
    /// 给用户的提示，比如为什么不能下、提了几个子。
    public private(set) var message: String?

    /// 等用户确认要换成的棋盘大小。不为 nil 时界面弹出确认框。
    public var pendingBoardSize: Int?
    public var isConfirmingClear = false

    private var nextAlternateStone: Stone = .black
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    private struct Snapshot {
        var position: Position
        var lastMove: Point?
    }

    public init(problem: Problem = .sample) {
        self.problem = problem
        position = problem.startPosition
    }

    // MARK: - 显示

    public var displayedBoard: Board { mode == .setup ? problem.setup : position.board }

    /// 摆题时显示全盘，方便往任何地方放子；做题时默认只显示题目所在的局部。
    public var region: BoardRegion {
        if mode == .setup || showWholeBoard { return .full(size: problem.setup.size) }
        return .fitting(problem.setup)
    }

    /// 只在原来那颗子还在时显示它上面的字，被提掉后就不显示了。
    public var displayedLabels: [Point: String] {
        let board = displayedBoard
        return problem.labels.filter { board[$0.key] == problem.setup[$0.key] }
    }

    public var ghost: GhostStone? {
        guard mode == .solve, let pending else { return nil }
        return GhostStone(point: pending, stone: position.toPlay)
    }

    /// 摆题时没有气的子，界面用红圈标出来。
    public var stonesWithoutLiberties: Set<Point> {
        Set(problem.setup.groupsWithoutLiberties.flatMap { $0 })
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - 操作

    public func switchMode(to newMode: EditorMode) {
        guard newMode != mode else { return }
        mode = newMode
        if newMode == .solve { restart() }
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

    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(Snapshot(position: position, lastMove: lastMove))
        position = snapshot.position
        lastMove = snapshot.lastMove
        pending = nil
        message = nil
    }

    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(Snapshot(position: position, lastMove: lastMove))
        position = snapshot.position
        lastMove = snapshot.lastMove
        pending = nil
        message = nil
    }

    /// 回到摆好的局面重新做。
    public func restart() {
        position = problem.startPosition
        lastMove = nil
        undoStack.removeAll()
        redoStack.removeAll()
        pending = nil
        message = nil
    }

    // MARK: - 内部

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
        if confirmMoves && pending != p {
            if position.board[p] != nil {
                pending = nil
                message = MoveError.occupied.message
            } else {
                pending = p
                message = nil
            }
            return
        }
        pending = nil
        do throws(MoveError) {
            let result = try position.playing(p)
            undoStack.append(Snapshot(position: position, lastMove: lastMove))
            redoStack.removeAll()
            position = result.position
            lastMove = p
            message = result.captured.isEmpty ? nil : "提掉 \(result.captured.count) 个子"
        } catch {
            message = error.message
        }
    }
}
