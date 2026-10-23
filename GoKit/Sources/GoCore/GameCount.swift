/// 对弈结束时按中国规则数子的结果。
public struct GameCount: Sendable, Equatable {
    /// 黑方的子数：活子加围住的空点。
    public var black: Int
    public var white: Int
    /// 白方贴的子数。
    public var komi: Double
    /// 算成死子、数子时先拿掉的子。
    public var dead: Set<Point>
    /// 每个点归谁，包括死子拿掉以后的点。两种颜色都碰到的空点不在里面。
    public var owner: [Point: Stone]
    /// 判过死子。没有引擎或者引擎出错时为 false，棋盘上的子都算活的。
    public var judgedDead: Bool

    public init(board: Board, dead: Set<Point> = [], komi: Double, judgedDead: Bool = true) {
        let counted = board.count(dead: dead)
        black = counted.black
        white = counted.white
        owner = counted.owner
        self.komi = komi
        self.dead = dead
        self.judgedDead = judgedDead
    }

    /// 黑方赢了多少，白方赢时是负数。
    public var margin: Double { Double(black) - Double(white) - komi }
}

extension Board {
    /// 中国规则数子：拿掉死子，每方的活子加上只碰到自己颜色的空地。两种颜色都碰到的空地（公气、双活里的空）不算。
    public func count(dead: Set<Point>) -> (black: Int, white: Int, owner: [Point: Stone]) {
        var board = self
        for p in dead { board[p] = nil }
        var owner: [Point: Stone] = [:]
        for p in board.occupiedPoints { owner[p] = board[p] }
        var seen = Set<Point>()
        for start in board.allPoints where board[start] == nil && !seen.contains(start) {
            // 一片连着的空地，看它碰到哪些颜色。
            var region: [Point] = [start]
            var borders = Set<Stone>()
            var stack = [start]
            seen.insert(start)
            while let q = stack.popLast() {
                for n in board.neighbors(of: q) {
                    if let stone = board[n] {
                        borders.insert(stone)
                    } else if !seen.contains(n) {
                        seen.insert(n)
                        region.append(n)
                        stack.append(n)
                    }
                }
            }
            if borders.count == 1, let color = borders.first {
                for p in region { owner[p] = color }
            }
        }
        let black = owner.values.lazy.filter { $0 == .black }.count
        return (black, owner.count - black, owner)
    }
}
