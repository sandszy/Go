/// 不能落子的原因。
public enum MoveError: Error, Equatable, Sendable {
    case outOfBounds
    case occupied
    case suicide
    case ko

    /// 给孩子看的说明。
    public var message: String {
        switch self {
        case .outOfBounds: "这里不在棋盘上"
        case .occupied: "这里已经有棋子了"
        case .suicide: "这里是禁入点：下进去自己就没有气了"
        case .ko: "打劫：要先在别处下一手，才能提回来"
        }
    }
}

/// 落子的结果：新局面和被提掉的子。
public struct MoveResult: Sendable {
    public let position: Position
    public let captured: [Point]
}

/// 可以接着下的局面：盘面、轮到谁、打劫时不能下的点、双方提子数。
/// 规则按中国规则：禁止自杀，打劫用简单劫判断。
public struct Position: Hashable, Codable, Sendable {
    public private(set) var board: Board
    public private(set) var toPlay: Stone
    /// 因为打劫，这一手不能下的点。
    public private(set) var koPoint: Point?
    /// 黑方提掉的白子数。
    public private(set) var blackCaptures = 0
    /// 白方提掉的黑子数。
    public private(set) var whiteCaptures = 0

    public init(board: Board, toPlay: Stone = .black) {
        self.board = board
        self.toPlay = toPlay
    }

    public func captures(by stone: Stone) -> Int {
        stone == .black ? blackCaptures : whiteCaptures
    }

    /// 轮到的一方在 p 落子。不合法时抛出原因，局面不变。
    public func playing(_ p: Point) throws(MoveError) -> MoveResult {
        guard board.contains(p) else { throw .outOfBounds }
        guard board[p] == nil else { throw .occupied }
        guard p != koPoint else { throw .ko }

        let me = toPlay
        var next = board
        next[p] = me

        var captured: [Point] = []
        for n in next.neighbors(of: p) where next[n] == me.opponent {
            let group = next.group(at: n)
            if next.liberties(of: group).isEmpty {
                for q in group { next[q] = nil }
                captured.append(contentsOf: group)
            }
        }

        let myGroup = next.group(at: p)
        let myLiberties = next.liberties(of: myGroup)
        guard !myLiberties.isEmpty else { throw .suicide }

        var result = self
        result.board = next
        result.toPlay = me.opponent
        // 只提一子、落下的子单独一个且只剩一口气（就是刚提的那个点），
        // 对方马上提回会回到原来的样子，这就是打劫。
        if captured.count == 1, myGroup.count == 1, myLiberties.count == 1 {
            result.koPoint = captured[0]
        } else {
            result.koPoint = nil
        }
        if me == .black {
            result.blackCaptures += captured.count
        } else {
            result.whiteCaptures += captured.count
        }
        return MoveResult(position: result, captured: captured)
    }

    public func isLegal(_ p: Point) -> Bool {
        (try? playing(p)) != nil
    }

    /// 停一手，劫的限制随之解除。
    public func passing() -> Position {
        var result = self
        result.toPlay = toPlay.opponent
        result.koPoint = nil
        return result
    }
}
