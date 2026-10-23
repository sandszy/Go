/// 把题目外面的空棋盘填满，让引擎只关心题目这一块。
///
/// 围棋引擎是按整盘棋下的：题目外面空着一大片时，它会觉得去别处占地更划算，局部的死活反而不管了。
/// 所以在题目区域外面摆上两种颜色、都已经活净的棋子，再按两边外框的目数定贴目。
/// 这样全盘的输赢只取决于题目这一块，引擎算出的目数差就是这一块的得失。
public struct TsumegoFrame: Sendable {
    /// 摆好外框以后的棋盘。题目区域里和原题一样。
    public let board: Board
    /// 留给题目的区域，区域外都是外框。
    public let area: BoardRegion
    /// 让两边外框的目数大致相当的贴目（日本规则，数目：外框里的眼就是目）。
    public let komi: Double

    /// 题目区域外的空间太小、或者棋盘太小时不加外框，直接用原棋盘。
    public init(problem: Problem) {
        let setup = problem.setup
        let size = setup.size
        var area = Self.area(for: problem)
        let unframed = (board: setup, area: BoardRegion.full(size: size), komi: 6.5)

        let wall = Self.wallColor(for: problem)
        switch problem.goal {
        case .capturingRace:
            // 对杀等题的外框贴着棋子外面一路摆。题目里没子的空地留着的话，引擎觉得去那里占地比对杀划算；
            // 输的一方也会往空地里跑，拖着孩子一路追。
            // 吃子、逃子、做活、杀棋题不这样收紧：能不能跑出去、做不做得出眼，和外面有多少空地有关。
            area = BoardRegion.fitting(setup, margin: 1, snap: 1, minSpan: 1)
        case .capture, .escape:
            break
        }
        let sides = Self.sideColors(for: problem, area: area)
        guard size >= 13, area.width * area.height * 2 <= size * size,
              let fill = Self.fill(setup: setup, area: area, sides: sides) ?? Self.fill(setup: setup, area: area, wall: wall)
        else {
            (board, self.area, komi) = unframed
            return
        }
        board = fill.board
        self.area = area
        komi = fill.komi
    }

    /// 不加外框，整个棋盘都是区域。对弈用。
    public init(whole board: Board, komi: Double) {
        self.board = board
        area = .full(size: board.size)
        self.komi = komi
    }

    /// 题目区域里离所有棋子都超过 distance 路的空点。
    /// 外框两种颜色交界的地方会空出一片，引擎觉得去那里占地比做题划算；搜索时让双方都不下这些点。
    /// 按当前局面算，逃子时棋子往外走，能下的范围也跟着走。
    public func distantPoints(on board: Board, distance: Int = 2) -> [Point] {
        let stones = area.points.filter { board[$0] != nil }
        return area.points.filter { p in
            board[p] == nil && !stones.contains { max(abs($0.x - p.x), abs($0.y - p.y)) <= distance }
        }
    }

    /// 题目区域：印出来的那一块，再保证每个子外面至少还有两路空地。
    static func area(for problem: Problem) -> BoardRegion {
        var area = BoardRegion.fitting(problem.setup)
        if let printed = problem.region {
            area.minX = min(area.minX, printed.minX)
            area.minY = min(area.minY, printed.minY)
            area.maxX = max(area.maxX, printed.maxX)
            area.maxY = max(area.maxY, printed.maxY)
        }
        return area
    }

    /// 紧贴题目区域的外框用哪种颜色。
    ///
    /// 子跑到区域边上就和这种颜色的外框连上了，所以要看谁"跑出去"算成功：
    /// 逃子、杀棋题是做题方（杀棋时做题方在外面包围），吃子、做活题是对方（做活时对方在外面包围）。
    /// 对杀等题看哪方的子离棋盘边更远：在外面包围的一方子更靠中间（KaTrain、Lizgoban 的死活外框也这样猜）。
    public static func wallColor(for problem: Problem) -> Stone {
        let me = problem.toPlay
        switch problem.goal {
        case .escape: return me
        case .capture: return me.opponent
        case .capturingRace:
            let setup = problem.setup
            let last = setup.size - 1
            var balance = 0
            for p in setup.occupiedPoints {
                let height = min(p.x, p.y, last - p.x, last - p.y)
                balance += setup[p] == .black ? height : -height
            }
            if balance == 0 { return me.opponent }
            return balance > 0 ? .black : .white
        }
    }

    /// 区域的一条边。
    enum Side: CaseIterable {
        case top, bottom, left, right
    }

    /// 对杀、连接、切断题，外框每条边各用离那条边最近的子的颜色：
    /// 题目上边是黑子、右边是白子时，上边摆黑框、右边摆白框，两边在外面的子都算活的，只剩题目里的对杀。
    /// 整个外框只用一种颜色的话，另一方在外面的子会被外框围住，引擎就去救它们，不管题目了。
    /// 各边颜色都一样时返回 nil，按 wallColor 摆。吃子、逃子、做活、杀棋题看题目要谁跑出去，也返回 nil。
    static func sideColors(for problem: Problem, area: BoardRegion) -> [Side: Stone]? {
        guard problem.goal == .capturingRace else { return nil }
        let setup = problem.setup
        let last = setup.size - 1
        let fallback = wallColor(for: problem)
        var colors: [Side: Stone] = [:]
        for side in Side.allCases {
            func distance(_ p: Point) -> Int {
                switch side {
                case .top: p.y - area.minY
                case .bottom: area.maxY - p.y
                case .left: p.x - area.minX
                case .right: area.maxX - p.x
                }
            }
            let open = switch side {
            case .top: area.minY > 0
            case .bottom: area.maxY < last
            case .left: area.minX > 0
            case .right: area.maxX < last
            }
            guard open else { continue }
            // 离这条边最近的一两排子里，哪种颜色多。
            let stones = setup.occupiedPoints
            guard let nearest = stones.map(distance).min() else { continue }
            let near = stones.filter { distance($0) <= nearest + 1 }
            let black = near.filter { setup[$0] == .black }.count
            let white = near.count - black
            colors[side] = black == white ? fallback : (black > white ? .black : .white)
        }
        return Set(colors.values).count > 1 ? colors : nil
    }

    /// 区域外的点属于哪条边外面。区域斜对角外面的点算上下边的。
    static func side(of p: Point, outside area: BoardRegion) -> Side {
        if p.y < area.minY { return .top }
        if p.y > area.maxY { return .bottom }
        return p.x < area.minX ? .left : .right
    }

    /// 每条边外面整片用那条边的颜色。哪块活不了就返回 nil。
    private static func fill(setup: Board, area: BoardRegion, sides: [Side: Stone]?) -> (board: Board, komi: Double)? {
        guard let sides else { return nil }
        let outside = setup.allPoints.filter { !area.contains($0) }
        var board = setup
        for p in outside {
            guard let color = sides[side(of: p, outside: area)] else { return nil }
            board[p] = color
        }
        return finish(board, frame: Set(outside))
    }

    /// 撒上眼位；外框的每一块都有两只眼才算摆好。
    /// 贴目让两边外框的目数（眼）相当，KataGo 的贴目最多 ±150。
    private static func finish(_ filled: Board, frame: Set<Point>) -> (board: Board, komi: Double)? {
        var board = filled
        let eyes = eyePoints(on: board, frame: frame)
        guard everyGroupLives(on: board, frame: frame, eyes: eyes) else { return nil }
        let blackEyes = eyes.filter { board[$0] == .black }.count
        for p in eyes { board[p] = nil }
        let komi = Double(blackEyes * 2 - eyes.count) + 0.5
        return (board, min(149.5, max(-149.5, komi)))
    }

    /// 区域外按离区域的远近分两圈：近的一圈是 wall 色，远的是另一色，每块都留出足够的眼。
    /// 找不到两块都能活的分法时，整片外框都用 wall 色；还不行就返回 nil。
    private static func fill(setup: Board, area: BoardRegion, wall: Stone) -> (board: Board, komi: Double)? {
        let outside = setup.allPoints.filter { !area.contains($0) }
        let distance = Dictionary(uniqueKeysWithValues: outside.map { p in
            (p, max(area.minX - p.x, p.x - area.maxX, area.minY - p.y, p.y - area.maxY))
        })
        let farthest = distance.values.max() ?? 0

        // 近圈至少 3 路宽，中间那路才能留眼；远圈也一样。挑两边子数最接近的分法。
        var options: [Int] = Array(stride(from: 3, through: farthest - 3, by: 1))
        options.sort { lhs, rhs in
            func imbalance(_ t: Int) -> Int {
                let near = distance.values.filter { $0 <= t }.count
                return abs(near * 2 - outside.count)
            }
            return imbalance(lhs) < imbalance(rhs)
        }
        options.append(farthest)

        let frame = Set(outside)
        for threshold in options {
            var board = setup
            for p in outside {
                board[p] = distance[p]! <= threshold ? wall : wall.opponent
            }
            if let result = finish(board, frame: frame) { return result }
        }
        return nil
    }

    /// 外框里隔开撒的空点，上下左右都是同色外框子，所以都是真眼。
    private static func eyePoints(on board: Board, frame: Set<Point>) -> Set<Point> {
        Set(frame.filter { p in
            guard (p.x + 2 * p.y) % 5 == 0 else { return false }
            return board.neighbors(of: p).allSatisfy { frame.contains($0) && board[$0] == board[p] }
        })
    }

    /// 去掉眼位以后，外框的每一块都至少有两只眼。
    private static func everyGroupLives(on board: Board, frame: Set<Point>, eyes: Set<Point>) -> Bool {
        var seen = eyes
        for p in frame where !seen.contains(p) {
            var group: Set<Point> = [p]
            var groupEyes = Set<Point>()
            var stack = [p]
            while let q = stack.popLast() {
                for n in board.neighbors(of: q) where frame.contains(n) && board[n] == board[p] {
                    if eyes.contains(n) {
                        groupEyes.insert(n)
                    } else if group.insert(n).inserted {
                        stack.append(n)
                    }
                }
            }
            seen.formUnion(group)
            if groupEyes.count < 2 { return false }
        }
        return true
    }
}
