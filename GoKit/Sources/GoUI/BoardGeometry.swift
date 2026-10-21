import CoreGraphics
import GoCore

/// 棋盘交叉点和视图坐标之间的换算。BoardView 画图和处理点击用的是同一份。
struct BoardGeometry {
    let region: BoardRegion
    /// 相邻两条线的间距。
    let spacing: CGFloat
    /// 区域左上角那个交叉点在视图里的位置。
    let origin: CGPoint

    /// 网格外留出的宽度（以线距为单位）：要放下边上的半颗棋子，显示坐标时还要放下标签。
    static func margin(showCoordinates: Bool) -> CGFloat { showCoordinates ? 1.3 : 0.75 }

    static func aspectRatio(region: BoardRegion, showCoordinates: Bool) -> CGFloat {
        let m = margin(showCoordinates: showCoordinates)
        return (CGFloat(region.width - 1) + 2 * m) / (CGFloat(region.height - 1) + 2 * m)
    }

    init(region: BoardRegion, showCoordinates: Bool, size: CGSize) {
        self.region = region
        let m = Self.margin(showCoordinates: showCoordinates)
        let columns = CGFloat(region.width - 1) + 2 * m
        let rows = CGFloat(region.height - 1) + 2 * m
        spacing = max(1, min(size.width / columns, size.height / rows))
        let gridWidth = CGFloat(region.width - 1) * spacing
        let gridHeight = CGFloat(region.height - 1) * spacing
        origin = CGPoint(x: (size.width - gridWidth) / 2, y: (size.height - gridHeight) / 2)
    }

    func position(of p: Point) -> CGPoint {
        CGPoint(
            x: origin.x + CGFloat(p.x - region.minX) * spacing,
            y: origin.y + CGFloat(p.y - region.minY) * spacing
        )
    }

    /// 点击位置对应的交叉点。离最近的交叉点太远（超过 0.6 个线距）时返回 nil。
    func point(at location: CGPoint) -> Point? {
        let column = Int(((location.x - origin.x) / spacing).rounded())
        let row = Int(((location.y - origin.y) / spacing).rounded())
        let p = Point(region.minX + column, region.minY + row)
        guard region.contains(p) else { return nil }
        let center = position(of: p)
        guard hypot(location.x - center.x, location.y - center.y) <= spacing * 0.6 else { return nil }
        return p
    }
}
