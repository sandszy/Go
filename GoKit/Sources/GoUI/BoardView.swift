import GoCore
import SwiftUI

/// 等待确认的落子位置，画成半透明的棋子。
public struct GhostStone: Equatable, Sendable {
    public var point: Point
    public var stone: Stone

    public init(point: Point, stone: Stone) {
        self.point = point
        self.stone = stone
    }
}

/// 棋盘。只负责画和把点击换算成交叉点，不管规则。
/// 只显示局部时，棋盘边线画粗线，没到边的一侧线条伸出去一点，和印刷题的样子一致。
public struct BoardView: View {
    public var board: Board
    public var region: BoardRegion
    public var labels: [Point: String]
    public var lastMove: Point?
    public var ghost: GhostStone?
    /// 用红圈标出的棋子，比如摆题时没有气的子。
    public var highlighted: Set<Point>
    public var showCoordinates: Bool
    public var onTap: ((Point) -> Void)?

    public init(
        board: Board,
        region: BoardRegion? = nil,
        labels: [Point: String] = [:],
        lastMove: Point? = nil,
        ghost: GhostStone? = nil,
        highlighted: Set<Point> = [],
        showCoordinates: Bool = false,
        onTap: ((Point) -> Void)? = nil
    ) {
        self.board = board
        self.region = region ?? .full(size: board.size)
        self.labels = labels
        self.lastMove = lastMove
        self.ghost = ghost
        self.highlighted = highlighted
        self.showCoordinates = showCoordinates
        self.onTap = onTap
    }

    public var body: some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(region: region, showCoordinates: showCoordinates, size: proxy.size)
            Canvas { context, size in
                draw(in: &context, size: size, geometry: geometry)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                if let p = geometry.point(at: value.location) { onTap?(p) }
            })
        }
        .aspectRatio(BoardGeometry.aspectRatio(region: region, showCoordinates: showCoordinates), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("棋盘，黑子 \(board.count(of: .black)) 个，白子 \(board.count(of: .white)) 个")
    }

    // MARK: - 绘制

    private func draw(in context: inout GraphicsContext, size: CGSize, geometry g: BoardGeometry) {
        let background = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: g.spacing * 0.3)
        context.fill(background, with: .color(Theme.wood))

        drawGrid(in: &context, g)
        for p in board.starPoints where region.contains(p) {
            let c = g.position(of: p)
            let r = g.spacing * 0.1
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.line))
        }
        if showCoordinates { drawCoordinates(in: &context, g) }

        let radius = g.spacing * 0.48
        for p in region.points {
            guard let stone = board[p] else { continue }
            drawStone(stone, at: g.position(of: p), radius: radius, in: &context)
        }
        if let ghost, region.contains(ghost.point), board[ghost.point] == nil {
            drawStone(ghost.stone, at: g.position(of: ghost.point), radius: radius, in: &context, opacity: 0.5)
        }
        drawMarks(in: &context, g, radius: radius)
    }

    private func drawGrid(in context: inout GraphicsContext, _ g: BoardGeometry) {
        let last = board.size - 1
        let overhang = g.spacing * 0.45
        let inner = StrokeStyle(lineWidth: max(1, g.spacing * 0.035))
        // 边线用方头，四个角上两条粗线才能接严。
        let edge = StrokeStyle(lineWidth: max(2, g.spacing * 0.08), lineCap: .square)
        let top = g.position(of: Point(region.minX, region.minY))
        let bottom = g.position(of: Point(region.maxX, region.maxY))
        // 没到棋盘边的一侧，线条往外伸一点。
        let minX = region.minX == 0 ? top.x : top.x - overhang
        let maxX = region.maxX == last ? bottom.x : bottom.x + overhang
        let minY = region.minY == 0 ? top.y : top.y - overhang
        let maxY = region.maxY == last ? bottom.y : bottom.y + overhang

        for x in region.minX...region.maxX {
            let px = g.position(of: Point(x, region.minY)).x
            var path = Path()
            path.move(to: CGPoint(x: px, y: minY))
            path.addLine(to: CGPoint(x: px, y: maxY))
            context.stroke(path, with: .color(Theme.line), style: x == 0 || x == last ? edge : inner)
        }
        for y in region.minY...region.maxY {
            let py = g.position(of: Point(region.minX, y)).y
            var path = Path()
            path.move(to: CGPoint(x: minX, y: py))
            path.addLine(to: CGPoint(x: maxX, y: py))
            context.stroke(path, with: .color(Theme.line), style: y == 0 || y == last ? edge : inner)
        }
    }

    private func drawCoordinates(in context: inout GraphicsContext, _ g: BoardGeometry) {
        let font = Font.system(size: g.spacing * 0.36, weight: .medium)
        let offset = g.spacing * 0.9
        for x in region.minX...region.maxX {
            let c = g.position(of: Point(x, region.maxY))
            let text = Text(Coordinates.columnLabel(x)).font(font).foregroundStyle(Theme.line)
            context.draw(text, at: CGPoint(x: c.x, y: c.y + offset))
        }
        for y in region.minY...region.maxY {
            let c = g.position(of: Point(region.minX, y))
            let text = Text(Coordinates.rowLabel(y, size: board.size)).font(font).foregroundStyle(Theme.line)
            context.draw(text, at: CGPoint(x: c.x - offset, y: c.y))
        }
    }

    private func drawStone(
        _ stone: Stone,
        at c: CGPoint,
        radius r: CGFloat,
        in context: inout GraphicsContext,
        opacity: Double = 1
    ) {
        let path = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        let light = CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.4)
        var layer = context
        layer.opacity = opacity
        if opacity == 1 {
            layer.addFilter(.shadow(color: .black.opacity(0.35), radius: r * 0.1, x: r * 0.06, y: r * 0.1))
        }
        switch stone {
        case .black:
            let gradient = Gradient(colors: [Color(white: 0.45), Color(white: 0.04)])
            layer.fill(path, with: .radialGradient(gradient, center: light, startRadius: 0, endRadius: r * 1.3))
        case .white:
            let gradient = Gradient(colors: [.white, Color(white: 0.8)])
            layer.fill(path, with: .radialGradient(gradient, center: light, startRadius: r * 0.1, endRadius: r * 1.5))
            layer.stroke(path, with: .color(Color(white: 0.45)), lineWidth: max(0.5, r * 0.04))
        }
    }

    private func drawMarks(in context: inout GraphicsContext, _ g: BoardGeometry, radius r: CGFloat) {
        for (p, label) in labels where region.contains(p) {
            let c = g.position(of: p)
            let stone = board[p]
            if stone == nil {
                // 空点上的字母要先盖住线条。
                let rect = CGRect(x: c.x - r * 0.6, y: c.y - r * 0.6, width: r * 1.2, height: r * 1.2)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.wood))
            }
            let color: Color = stone == .black ? .white : .black
            let text = Text(label).font(.system(size: g.spacing * 0.5, weight: .semibold)).foregroundStyle(color)
            context.draw(text, at: c)
        }
        if let lastMove, region.contains(lastMove), labels[lastMove] == nil, let stone = board[lastMove] {
            let c = g.position(of: lastMove)
            let ring = Path(ellipseIn: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.45, width: r * 0.9, height: r * 0.9))
            context.stroke(ring, with: .color(stone == .black ? .white : .black), lineWidth: r * 0.1)
        }
        for p in highlighted where region.contains(p) {
            let c = g.position(of: p)
            let ring = Path(ellipseIn: CGRect(x: c.x - r * 1.05, y: c.y - r * 1.05, width: r * 2.1, height: r * 2.1))
            context.stroke(ring, with: .color(.red), lineWidth: r * 0.14)
        }
    }
}
