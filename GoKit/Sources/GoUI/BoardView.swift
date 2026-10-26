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
    /// 用橙色虚线圈标出的点，比如识别照片时没认准的地方。
    public var uncertain: Set<Point>
    /// 数子时每个点归谁，画成小方块：空点上，以及死子上（画对方的颜色）。
    public var territory: [Point: Stone]
    public var showCoordinates: Bool
    /// 棋盘四周的画框颜色，比如区分摆题和做题/对弈（F1.7）。nil 就不画框，预览、截图小图不用这个。
    public var frameColor: Color?
    public var onTap: ((Point) -> Void)?

    @State private var flashColor: Color?

    public init(
        board: Board,
        region: BoardRegion? = nil,
        labels: [Point: String] = [:],
        lastMove: Point? = nil,
        ghost: GhostStone? = nil,
        highlighted: Set<Point> = [],
        uncertain: Set<Point> = [],
        territory: [Point: Stone] = [:],
        showCoordinates: Bool = false,
        frameColor: Color? = nil,
        onTap: ((Point) -> Void)? = nil
    ) {
        self.board = board
        self.region = region ?? .full(size: board.size)
        self.labels = labels
        self.lastMove = lastMove
        self.ghost = ghost
        self.highlighted = highlighted
        self.uncertain = uncertain
        self.territory = territory
        self.showCoordinates = showCoordinates
        self.frameColor = frameColor
        self.onTap = onTap
    }

    public var body: some View {
        GeometryReader { proxy in
            let geometry = BoardGeometry(region: region, showCoordinates: showCoordinates, size: proxy.size)
            let shape = RoundedRectangle(cornerRadius: geometry.spacing * 0.3, style: .continuous)
            let frameWidth = geometry.spacing * 0.055
            Canvas { context, size in
                draw(in: &context, size: size, geometry: geometry)
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                if let p = geometry.point(at: value.location) { onTap?(p) }
            })
            .overlay {
                shape
                    .strokeBorder(frameColor ?? .clear, lineWidth: frameWidth)
                    .animation(.easeOut(duration: 0.25), value: frameColor)
            }
            .overlay {
                // 扫光只盖在画框这圈细线上，不盖住棋盘本身，不然会把棋子、网格线一起扫过，太抢戏。
                if let flashColor {
                    ModeSwitchSweep(color: flashColor)
                        .mask(shape.stroke(lineWidth: frameWidth))
                        .allowsHitTesting(false)
                }
            }
        }
        .aspectRatio(BoardGeometry.aspectRatio(region: region, showCoordinates: showCoordinates), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("棋盘，黑子 \(board.count(of: .black)) 个，白子 \(board.count(of: .white)) 个")
        // 切模式瞬间画框颜色一变，就在棋盘上扫一道光，比只变颜色更"凌厉"、更容易注意到。
        .onChange(of: frameColor) { _, new in
            guard let new else { return }
            flashColor = new
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if flashColor == new { flashColor = nil }
            }
        }
    }

    // MARK: - 绘制

    private func draw(in context: inout GraphicsContext, size: CGSize, geometry g: BoardGeometry) {
        drawBoardSurface(in: &context, size: size, g)
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
        drawTerritory(in: &context, g, radius: radius)
        drawMarks(in: &context, g, radius: radius)
    }

    /// 木纹底色：径向渐变 + 很淡的暗角，和图标用同一套胡桃木质感，不加纹理线以免干扰读盘。
    private func drawBoardSurface(in context: inout GraphicsContext, size: CGSize, _ g: BoardGeometry) {
        let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: g.spacing * 0.3)
        let center = CGPoint(x: size.width * 0.4, y: size.height * 0.32)
        let radius = max(size.width, size.height) * 0.85
        context.fill(shape, with: .radialGradient(Theme.woodGradient, center: center, startRadius: 0, endRadius: radius))

        var vignette = context
        vignette.blendMode = .multiply
        let vignetteGradient = Gradient(stops: [
            .init(color: .white, location: 0.0),
            .init(color: .white, location: 0.62),
            .init(color: Color(white: 0.8), location: 1.0),
        ])
        vignette.fill(
            shape,
            with: .radialGradient(
                vignetteGradient,
                center: CGPoint(x: size.width * 0.5, y: size.height * 0.5),
                startRadius: 0,
                endRadius: max(size.width, size.height) * 0.75
            )
        )
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
        // 高光中心偏左上，棋子看起来像被从同一个方向打光，和图标一致。
        let light = CGPoint(x: c.x - r * 0.34, y: c.y - r * 0.4)

        // 棋子本体单独一层，阴影只加在这一层上。
        var body = context
        body.opacity = opacity
        if opacity == 1 {
            body.addFilter(.shadow(color: .black.opacity(0.4), radius: r * 0.12, x: r * 0.07, y: r * 0.12))
        }
        switch stone {
        case .black:
            body.fill(path, with: .radialGradient(Theme.blackStoneGradient, center: light, startRadius: 0, endRadius: r * 1.25))
            body.stroke(path, with: .color(Theme.blackStoneRim.opacity(0.25)), lineWidth: max(0.5, r * 0.02))
        case .white:
            body.fill(path, with: .radialGradient(Theme.whiteStoneGradient, center: light, startRadius: r * 0.05, endRadius: r * 1.3))
            body.stroke(path, with: .color(Theme.whiteStoneRim), lineWidth: max(0.5, r * 0.035))
        }

        // 玻璃光斑另开一层，不能带阴影滤镜，不然亮斑自己会投出一圈灰影，白子上特别明显。
        var sheen = context
        sheen.opacity = opacity
        sheen.clip(to: path)
        let glint = CGPoint(x: c.x - r * 0.38, y: c.y - r * 0.44)
        let glintRadius = r * 0.32
        let glintPath = Path(ellipseIn: CGRect(x: glint.x - glintRadius, y: glint.y - glintRadius, width: glintRadius * 2, height: glintRadius * 2))
        let glintGradient = Gradient(stops: [
            .init(color: .white.opacity(stone == .black ? 0.5 : 0.65), location: 0),
            .init(color: .white.opacity(stone == .black ? 0.15 : 0.2), location: 0.55),
            .init(color: .white.opacity(0), location: 1),
        ])
        sheen.fill(glintPath, with: .radialGradient(glintGradient, center: glint, startRadius: 0, endRadius: glintRadius))
    }

    /// 小方块边长约为棋子直径的三分之一，黑方块描白边、白方块描黑边，放在哪种子上都看得清。
    private func drawTerritory(in context: inout GraphicsContext, _ g: BoardGeometry, radius r: CGFloat) {
        let side = r * 0.66
        for (p, stone) in territory where region.contains(p) {
            let c = g.position(of: p)
            let square = Path(CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
            context.fill(square, with: .color(stone == .black ? .black : .white))
            context.stroke(square, with: .color(stone == .black ? .white : .black), lineWidth: max(0.5, r * 0.05))
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
        for p in uncertain where region.contains(p) {
            let c = g.position(of: p)
            let ring = Path(ellipseIn: CGRect(x: c.x - r * 1.05, y: c.y - r * 1.05, width: r * 2.1, height: r * 2.1))
            context.stroke(ring, with: .color(.orange), style: StrokeStyle(lineWidth: r * 0.14, dash: [r * 0.3, r * 0.2]))
        }
    }
}

/// 切模式瞬间在棋盘上扫过的一道斜向光带，0.25 秒扫完就淡出，配合画框颜色变化（F1.7）。
private struct ModeSwitchSweep: View {
    let color: Color
    @State private var t: CGFloat = -0.5

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: color.opacity(0), location: 0),
                .init(color: color.opacity(0.55), location: 0.5),
                .init(color: color.opacity(0), location: 1),
            ],
            startPoint: UnitPoint(x: t - 0.45, y: -0.2),
            endPoint: UnitPoint(x: t + 0.45, y: 1.2)
        )
        .blendMode(.plusLighter)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) {
                t = 1.5
            }
        }
    }
}
