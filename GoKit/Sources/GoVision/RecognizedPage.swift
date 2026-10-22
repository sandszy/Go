import CoreGraphics
import GoCore

/// 棋盘图哪几条外边是棋盘边（印得比较粗）。
public struct DiagramEdges: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = DiagramEdges(rawValue: 1 << 0)
    public static let right = DiagramEdges(rawValue: 1 << 1)
    public static let top = DiagramEdges(rawValue: 1 << 2)
    public static let bottom = DiagramEdges(rawValue: 1 << 3)
}

/// 棋盘图里的一个交叉点，从左上角数第几列、第几行（从 0 开始）。
public struct GridPoint: Hashable, Sendable {
    public var column: Int
    public var row: Int

    public init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }
}

/// 照片里认出来的一个棋盘图。
public struct RecognizedDiagram: Identifiable, Sendable {
    public let id: Int
    /// 印在旁边的题号。
    public var number: Int?
    /// 在原照片里的位置（像素，原点在左上角），选题和对照原图时用。
    public var bounds: CGRect
    public var columns: Int
    public var rows: Int
    public var edges: DiagramEdges
    /// stones[row][column]，从左上角数。
    public var stones: [[Stone?]]
    /// 印在交叉点上的数字，比如白子上的"1"。
    public var labels: [GridPoint: String]
    /// 认不准的交叉点，校对时提醒看一眼。
    public var uncertain: Set<GridPoint>
    /// 比同一页别的图小一圈，多半有一部分没拍进来（在照片边上、被反光或弯曲的书页挡住）。
    public var isIncomplete = false
    /// 中间有墨迹的白子在原照片里的位置，用来单独读上面的数字。
    var markedStones: [GridPoint: CGPoint] = [:]
    /// 其中墨迹像"1"的那些，文字识别读不出来时当作"1"。
    var oneShapedStones: Set<GridPoint> = []
    /// 线距，按原照片的像素算。
    var spacing: Double = 0

    public init(
        id: Int,
        number: Int?,
        bounds: CGRect,
        columns: Int,
        rows: Int,
        edges: DiagramEdges,
        stones: [[Stone?]],
        labels: [GridPoint: String] = [:],
        uncertain: Set<GridPoint> = []
    ) {
        self.id = id
        self.number = number
        self.bounds = bounds
        self.columns = columns
        self.rows = rows
        self.edges = edges
        self.stones = stones
        self.labels = labels
        self.uncertain = uncertain
    }

    init(
        id: Int,
        number: Int?,
        bounds: CGRect,
        columns: Int,
        rows: Int,
        edges: DiagramEdges,
        stones: [[Stone?]],
        labels: [GridPoint: String],
        uncertain: Set<GridPoint>,
        markedStones: [GridPoint: CGPoint],
        oneShapedStones: Set<GridPoint>,
        spacing: Double
    ) {
        self.init(id: id, number: number, bounds: bounds, columns: columns, rows: rows, edges: edges, stones: stones, labels: labels, uncertain: uncertain)
        self.markedStones = markedStones
        self.oneShapedStones = oneShapedStones
        self.spacing = spacing
    }

    /// 放到棋盘上：哪边是棋盘边就贴到哪边，都不是就放在中间。四边都是边、大小正好时就用那么大的棋盘。
    public var placement: (size: Int, x: Int, y: Int) {
        let size = edges == [.left, .right, .top, .bottom] && columns == rows && Board.supportedSizes.contains(columns) ? columns : 19
        let x = edges.contains(.left) ? 0 : edges.contains(.right) ? size - columns : (size - columns) / 2
        let y = edges.contains(.top) ? 0 : edges.contains(.bottom) ? size - rows : (size - rows) / 2
        return (size, max(0, x), max(0, y))
    }

    public func boardPoint(_ p: GridPoint) -> Point {
        let (_, x, y) = placement
        return Point(x + p.column, y + p.row)
    }

    public func problem(title: String, toPlay: Stone, goal: ProblemGoal?) -> Problem {
        let (size, x0, y0) = placement
        var board = Board(size: size)
        for row in 0..<rows {
            for column in 0..<columns {
                let p = Point(x0 + column, y0 + row)
                if board.contains(p) { board[p] = stones[row][column] }
            }
        }
        var labels: [Point: String] = [:]
        for (point, text) in self.labels { labels[boardPoint(point)] = text }
        let region = BoardRegion(
            minX: x0, minY: y0,
            maxX: min(size - 1, x0 + columns - 1), maxY: min(size - 1, y0 + rows - 1)
        )
        return Problem(title: title, setup: board, toPlay: toPlay, goal: goal, labels: labels, region: region)
    }
}

/// 一页作业纸的识别结果。
public struct RecognizedPage: Sendable {
    public var imageSize: CGSize
    /// 按题号排，没有题号的按从上到下、从左到右排。
    public var diagrams: [RecognizedDiagram]
    /// 页面上写的"黑先"或"白先"。
    public var toPlay: Stone?
    /// 从页面标题和说明猜的题目类型，比如"对杀"。
    public var goal: ProblemGoal?
    public var pageNumber: Int?

    public init(imageSize: CGSize, diagrams: [RecognizedDiagram], toPlay: Stone? = nil, goal: ProblemGoal? = nil, pageNumber: Int? = nil) {
        self.imageSize = imageSize
        self.diagrams = diagrams
        self.toPlay = toPlay
        self.goal = goal
        self.pageNumber = pageNumber
    }

    /// 题号中间断开的那些：这几道题照片上有，但没认出来（反光、阴影、没拍全）。
    public var missingNumbers: [Int] {
        let numbers = Set(diagrams.compactMap(\.number))
        guard let low = numbers.min(), let high = numbers.max(), high - low < 30 else { return [] }
        return (low...high).filter { !numbers.contains($0) }
    }

    /// "第 35 页第 7 题"，缺哪部分就省掉哪部分。
    public func title(for diagram: RecognizedDiagram) -> String {
        var parts: [String] = []
        if let pageNumber { parts.append("第 \(pageNumber) 页") }
        if let number = diagram.number { parts.append("第 \(number) 题") }
        return parts.joined()
    }

    public func problem(for diagram: RecognizedDiagram) -> Problem {
        diagram.problem(title: title(for: diagram), toPlay: toPlay ?? .black, goal: goal)
    }
}
