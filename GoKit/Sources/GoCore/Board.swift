/// 盘面：每个交叉点上是黑子、白子或空。只管放子和数气，不管轮到谁下。
public struct Board: Hashable, Codable, Sendable {
    public static let supportedSizes = [9, 13, 19]

    public let size: Int
    private var cells: [Stone?]

    public init(size: Int = 19) {
        precondition((2...25).contains(size), "不支持 \(size) 路棋盘")
        self.size = size
        cells = Array(repeating: nil, count: size * size)
    }

    public func contains(_ p: Point) -> Bool {
        p.x >= 0 && p.x < size && p.y >= 0 && p.y < size
    }

    public subscript(_ p: Point) -> Stone? {
        get { cells[index(of: p)] }
        set { cells[index(of: p)] = newValue }
    }

    private func index(of p: Point) -> Int {
        precondition(contains(p), "\(p) 不在 \(size) 路棋盘上")
        return p.y * size + p.x
    }

    /// 判题搜索时盘面要反复做哈希，直接对整块内存算，比逐格算快得多。
    public func hash(into hasher: inout Hasher) {
        hasher.combine(size)
        cells.withUnsafeBytes { hasher.combine(bytes: $0) }
    }

    public var isEmpty: Bool { cells.allSatisfy { $0 == nil } }

    public var allPoints: [Point] {
        (0..<size).flatMap { y in (0..<size).map { x in Point(x, y) } }
    }

    public var occupiedPoints: [Point] { allPoints.filter { self[$0] != nil } }

    public func count(of stone: Stone) -> Int { cells.lazy.filter { $0 == stone }.count }

    public func neighbors(of p: Point) -> [Point] {
        [Point(p.x - 1, p.y), Point(p.x + 1, p.y), Point(p.x, p.y - 1), Point(p.x, p.y + 1)]
            .filter(contains)
    }

    /// 和 p 连在一起的同色棋子，也就是一块棋。p 上没有棋子时返回空集合。
    public func group(at p: Point) -> Set<Point> {
        guard let color = self[p] else { return [] }
        var group: Set<Point> = [p]
        var stack = [p]
        while let q = stack.popLast() {
            for n in neighbors(of: q) where self[n] == color && !group.contains(n) {
                group.insert(n)
                stack.append(n)
            }
        }
        return group
    }

    public func liberties(of group: Set<Point>) -> Set<Point> {
        var liberties = Set<Point>()
        for q in group {
            for n in neighbors(of: q) where self[n] == nil {
                liberties.insert(n)
            }
        }
        return liberties
    }

    /// p 所在那块棋的气。
    public func liberties(at p: Point) -> Set<Point> { liberties(of: group(at: p)) }

    /// 和 group 贴着的某种颜色的块。
    public func neighborGroups(of group: Set<Point>, color: Stone) -> [Set<Point>] {
        var seen = Set<Point>()
        var result: [Set<Point>] = []
        for q in group {
            for n in neighbors(of: q) where self[n] == color && !seen.contains(n) {
                let g = self.group(at: n)
                seen.formUnion(g)
                result.append(g)
            }
        }
        return result
    }

    /// 盘面上所有的块。
    public var groups: [Set<Point>] {
        var seen = Set<Point>()
        var result: [Set<Point>] = []
        for p in occupiedPoints where !seen.contains(p) {
            let g = group(at: p)
            seen.formUnion(g)
            result.append(g)
        }
        return result
    }

    /// 没有气的块。摆题时可能摆出这种不可能出现的局面，界面要提醒。
    public var groupsWithoutLiberties: [Set<Point>] {
        groups.filter { liberties(of: $0).isEmpty }
    }

    public var starPoints: [Point] {
        let lines: [Int]
        switch size {
        case 19: lines = [3, 9, 15]
        case 13: lines = [3, 6, 9]
        case 9: lines = [2, 4, 6]
        default: return []
        }
        let points = lines.flatMap { x in lines.map { y in Point(x, y) } }
        // 13 路和 9 路只标四个角星和天元。
        guard size != 19 else { return points }
        let center = size / 2
        return points.filter { ($0.x == center) == ($0.y == center) }
    }
}

extension Board {
    /// 用字符画摆盘，方便写测试和示例题：X 黑，O 白，其他字符为空，空白字符忽略。
    /// 第一行是棋盘最上面一行，行数就是棋盘路数。
    public init(diagram: String) {
        let rows = diagram.split(separator: "\n")
            .map { $0.filter { !$0.isWhitespace } }
            .filter { !$0.isEmpty }
        self.init(size: rows.count)
        for (y, row) in rows.enumerated() {
            precondition(row.count == rows.count, "第 \(y + 1) 行有 \(row.count) 个点，应为 \(rows.count) 个")
            for (x, char) in row.enumerated() {
                switch char {
                case "X": self[Point(x, y)] = .black
                case "O": self[Point(x, y)] = .white
                default: break
                }
            }
        }
    }

    /// 和 init(diagram:) 对应的字符画，测试失败时方便看。
    public var diagram: String {
        (0..<size).map { y in
            String((0..<size).map { x in
                switch self[Point(x, y)] {
                case .black: "X"
                case .white: "O"
                case nil: "."
                }
            })
        }.joined(separator: "\n")
    }
}
