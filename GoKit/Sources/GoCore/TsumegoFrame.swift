/// 把题目外面的空棋盘填满，让引擎只关心题目这一块。
///
/// 围棋引擎是按整盘棋下的：题目外面空着一大片时，它会觉得去别处占地更划算，局部的死活反而不管了。
/// 所以在题目区域外面摆上两种颜色、都已经活净的棋子，再按两边的目数定贴目。
/// 这样全盘的输赢只取决于题目这一块，引擎算出的目数差就是这一块的得失。
public struct TsumegoFrame: Sendable {
    /// 摆好外框以后的棋盘。题目区域里和原题一样。
    public let board: Board
    /// 留给题目的区域，区域外都是外框。
    public let area: BoardRegion
    /// 让两边外框的目数大致相当的贴目（日本规则，按目数算）。
    public let komi: Double

    /// 题目区域外的空间太小、或者棋盘太小时不加外框，直接用原棋盘。
    public init(problem: Problem) {
        let setup = problem.setup
        let size = setup.size
        let area = Self.area(for: problem)
        let unframed = (board: setup, area: BoardRegion.full(size: size), komi: 6.5)

        guard size >= 13, area.width * area.height * 2 <= size * size,
              let fill = Self.fill(setup: setup, area: area, wall: Self.wallColor(for: problem))
        else {
            (board, self.area, komi) = unframed
            return
        }
        board = fill.board
        self.area = area
        komi = fill.komi
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
    /// 逃子题是做题方，吃子题是被吃的一方，做活题是杀棋方（活棋要在里面做眼），杀棋题是做题方。
    /// 对杀等其他题看哪方的子离棋盘边更远：在外面包围的一方子更靠中间（KaTrain、Lizgoban 的死活外框也这样猜）。
    static func wallColor(for problem: Problem) -> Stone {
        let me = problem.toPlay
        switch problem.goal {
        case .escape: return me
        case .capture: return me.opponent
        case .live: return me.opponent
        case .kill: return me
        case .capturingRace, .connect, .cut, nil:
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
            let eyes = eyePoints(on: board, frame: frame)
            guard everyGroupLives(on: board, frame: frame, eyes: eyes) else { continue }
            let blackEyes = eyes.filter { board[$0] == .black }.count
            for p in eyes { board[p] = nil }
            return (board, Double(blackEyes * 2 - eyes.count) + 0.5)
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
