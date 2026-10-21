/// 棋盘上的一块矩形区域，用来只显示题目所在的局部。两端都包含在内。
public struct BoardRegion: Hashable, Codable, Sendable {
    public var minX: Int
    public var minY: Int
    public var maxX: Int
    public var maxY: Int

    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public static func full(size: Int) -> BoardRegion {
        BoardRegion(minX: 0, minY: 0, maxX: size - 1, maxY: size - 1)
    }

    public var width: Int { maxX - minX + 1 }
    public var height: Int { maxY - minY + 1 }

    public func contains(_ p: Point) -> Bool {
        (minX...maxX).contains(p.x) && (minY...maxY).contains(p.y)
    }

    public var points: [Point] {
        (minY...maxY).flatMap { y in (minX...maxX).map { x in Point(x, y) } }
    }

    /// 刚好装下所有棋子的区域：四周各留 margin 路，离边线不超过 snap 路就直接扩到边线，
    /// 宽高都至少 minSpan 路。盘面上没有棋子时返回全盘。
    public static func fitting(_ board: Board, margin: Int = 2, snap: Int = 3, minSpan: Int = 7) -> BoardRegion {
        let points = board.occupiedPoints
        guard let first = points.first else { return .full(size: board.size) }

        var region = BoardRegion(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for p in points {
            region.minX = min(region.minX, p.x)
            region.minY = min(region.minY, p.y)
            region.maxX = max(region.maxX, p.x)
            region.maxY = max(region.maxY, p.y)
        }

        let last = board.size - 1
        region.minX = max(0, region.minX - margin)
        region.minY = max(0, region.minY - margin)
        region.maxX = min(last, region.maxX + margin)
        region.maxY = min(last, region.maxY + margin)

        if region.minX <= snap { region.minX = 0 }
        if region.minY <= snap { region.minY = 0 }
        if last - region.maxX <= snap { region.maxX = last }
        if last - region.maxY <= snap { region.maxY = last }

        // 太窄时往远离边线的方向扩。
        let span = min(minSpan, board.size)
        while region.width < span {
            if region.maxX < last { region.maxX += 1 } else { region.minX -= 1 }
        }
        while region.height < span {
            if region.maxY < last { region.maxY += 1 } else { region.minY -= 1 }
        }
        return region
    }
}

/// 坐标的写法：列用字母 A–T（跳过 I），行用数字，最下面一行是 1。
public enum Coordinates {
    private static let columnLetters = Array("ABCDEFGHJKLMNOPQRSTUVWXYZ")

    public static func columnLabel(_ x: Int) -> String {
        x < columnLetters.count ? String(columnLetters[x]) : String(x + 1)
    }

    public static func rowLabel(_ y: Int, size: Int) -> String { String(size - y) }

    public static func name(of p: Point, size: Int) -> String {
        columnLabel(p.x) + rowLabel(p.y, size: size)
    }
}
