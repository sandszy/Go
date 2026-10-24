import CoreGraphics
import Foundation
import GoCore

/// 识别一页印刷习题：找出每个棋盘图，认出上面的棋子，再读页面上的"黑先"、题型、题号和页码。
/// 计算量大，要在后台调用。
public enum PageRecognizer {
    /// 工作图的长边。线距大约 40 像素，够认清棋子，又不会太慢。
    static let workingSize = 2000

    public static func recognize(_ image: CGImage) throws -> RecognizedPage {
        guard let gray = GrayImage(image, maxDimension: workingSize) else {
            return RecognizedPage(imageSize: CGSize(width: image.width, height: image.height), diagrams: [])
        }
        // 窗口要比棋子大得多，黑子中间才不会被当成纸。
        let ink = gray.inkMask(window: max(31, gray.width / 12), ratio: 0.72)
        // 线点图：比两侧都暗的点。手晃糊了的浅线按局部阈值不是墨，这里还在（技术架构 D19）。
        let ridges = gray.ridges(distance: GridDetector.lineGap(width: gray.width))
        let toOriginal = Double(image.width) / Double(gray.width)

        let found = GridDetector.detect(in: ink, ridges: ridges)
        let made = found.grids.enumerated().map { index, grid in
            makeDiagram(id: index, grid: grid, ink: ink, ridges: ridges, gray: gray, shadows: found.shadows, scale: toOriginal)
        }
        var diagrams = made.map(\.diagram)
        dropFaintBlacks(&diagrams, darkness: made.map(\.darkness))
        clearShadowLines(&diagrams)

        // 按阅读顺序排：先上下（差不多一行的算同一行），再左右。练习册的题号也是这么排的。
        diagrams.sort { a, b in
            if abs(a.bounds.minY - b.bounds.minY) > a.bounds.height / 2 { return a.bounds.minY < b.bounds.minY }
            return a.bounds.minX < b.bounds.minX
        }

        let text = (try? TextReader.read(image)) ?? []
        assignNumbers(to: &diagrams, from: text)
        for index in diagrams.indices where diagrams[index].number == nil {
            diagrams[index].number = readBadgeNumber(beside: diagrams[index], image: image)
                ?? readRingedNumber(beside: diagrams[index], image: image, ink: ink, scale: toOriginal)
        }
        fillNumberSequence(&diagrams)
        markIncomplete(&diagrams)
        for index in diagrams.indices {
            diagrams[index].labels = readLabels(on: diagrams[index], image: image)
        }

        return RecognizedPage(
            imageSize: CGSize(width: image.width, height: image.height),
            diagrams: diagrams,
            toPlay: TextReader.toPlay(in: text),
            goal: TextReader.goal(in: text),
            pageNumber: pageNumber(in: text, imageHeight: Double(image.height), diagrams: diagrams, ink: ink, scale: toOriginal)
                ?? readPageNumberStrip(of: image, below: diagrams, ink: ink, scale: toOriginal)
                ?? readPageNumberBlobs(of: image, below: diagrams, ink: ink, scale: toOriginal)
        )
    }

    /// 页码条整条读不出来时（小字在大片空白里，有的设备上找不到），先找出像数字的那一小团墨迹，只裁那一块读。
    private static func readPageNumberBlobs(of image: CGImage, below diagrams: [RecognizedDiagram], ink: InkMask, scale: Double) -> Int? {
        guard let spacing = median(diagrams.map { $0.spacing / scale }) else { return nil }
        let height = Double(image.height)
        let top = height * 0.8
        let strip = CGRect(x: 0, y: top, width: Double(image.width), height: height - top)
        let blobs = GlyphReader.textBlobs(in: ink, area: strip, scale: scale, minHeight: spacing * 0.3, maxHeight: spacing * 1.2)
        for blob in blobs where !isOnDiagram(blob, diagrams) && !isInsideBadge(blob, diagrams: diagrams, ink: ink, scale: scale) {
            let padded = blob.insetBy(dx: -blob.height * 0.6, dy: -blob.height * 0.6)
            guard let crop = PhotoLoader.crop(image, to: padded) else { continue }
            for fast in [false, true] {
                let items = (try? TextReader.read(crop, minimumTextHeight: 0, languages: ["en-US"], fast: fast)) ?? []
                if let number = items.lazy.compactMap({ TextReader.number(in: $0.text) }).first { return number }
            }
        }
        return nil
    }

    /// 印的黑子是实心的黑；铅笔印、橡皮屑是灰的，大小又和棋子差不多，墨迹图上分不出来。
    /// 比一比黑子中间有多黑（和周围的纸比），比这一页大多数黑子浅得多的不是黑子，标成没认准。
    /// 按这一页的黑子比，不定死一个数：光线暗、对比度低的照片，黑子也没那么黑。
    static func dropFaintBlacks(_ diagrams: inout [RecognizedDiagram], darkness: [[GridPoint: Double]]) {
        guard let typical = median(darkness.flatMap(\.values)) else { return }
        let limit = max(0.33, typical * 1.6)
        for index in diagrams.indices {
            for (point, value) in darkness[index] where value > limit {
                diagrams[index].stones[point.row][point.column] = nil
                diagrams[index].uncertain.insert(point)
            }
        }
    }

    /// 书页卷得厉害时，挤在书缝阴影里的最外面一列会认成一整列黑子。题目不会在不是棋盘边的最外面一列（行）摆满黑子，
    /// 这样的一列（行）三分之二以上是黑子的，整列清空，留成空点，标成没认准。
    static func clearShadowLines(_ diagrams: inout [RecognizedDiagram]) {
        for index in diagrams.indices {
            let d = diagrams[index]
            guard d.columns >= 3, d.rows >= 3 else { continue }
            var lines: [[GridPoint]] = []
            if !d.edges.contains(.left) { lines.append((0..<d.rows).map { GridPoint(column: 0, row: $0) }) }
            if !d.edges.contains(.right) { lines.append((0..<d.rows).map { GridPoint(column: d.columns - 1, row: $0) }) }
            if !d.edges.contains(.top) { lines.append((0..<d.columns).map { GridPoint(column: $0, row: 0) }) }
            if !d.edges.contains(.bottom) { lines.append((0..<d.columns).map { GridPoint(column: $0, row: d.rows - 1) }) }
            for line in lines {
                let blacks = line.filter { d.stones[$0.row][$0.column] == .black }
                guard blacks.count >= 3, blacks.count * 3 >= line.count * 2 else { continue }
                for point in blacks {
                    diagrams[index].stones[point.row][point.column] = nil
                    diagrams[index].uncertain.insert(point)
                }
            }
        }
    }

    /// 离中心 0.22 到 0.38 格那一圈的灰度中位数，除以周围（三格见方）的纸的亮度。
    /// 不看正中间：黑子上印着白色的数字（❷）。铅笔印比棋子小，这一圈大半是纸。
    private static func darkness(at center: (x: Double, y: Double), spacing s: Double, gray: GrayImage) -> Double {
        var core: [UInt8] = [], around: [UInt8] = []
        let reach = Int(s * 1.5), inner = s * 0.22, outer = s * 0.38
        for dy in stride(from: -reach, through: reach, by: 2) {
            for dx in stride(from: -reach, through: reach, by: 2) {
                let x = Int(center.x) + dx, y = Int(center.y) + dy
                guard x >= 0, y >= 0, x < gray.width, y < gray.height else { continue }
                let d2 = Double(dx * dx + dy * dy)
                if d2 >= inner * inner && d2 <= outer * outer { core.append(gray[x, y]) }
                around.append(gray[x, y])
            }
        }
        guard !core.isEmpty else { return 0 }
        core.sort(); around.sort()
        let paper = max(1, Double(around[around.count * 9 / 10]))
        return Double(core[core.count / 2]) / paper
    }

    private static func makeDiagram(
        id: Int, grid: DetectedGrid, ink: InkMask, ridges: (horizontal: InkMask, vertical: InkMask), gray: GrayImage, shadows: InkMask, scale: Double
    ) -> (diagram: RecognizedDiagram, darkness: [GridPoint: Double]) {
        var blacks: [GridPoint: Double] = [:]
        var stones: [[Stone?]] = []
        var uncertain = Set<GridPoint>()
        var marked: [GridPoint: CGPoint] = [:]
        var ones = Set<GridPoint>()
        for row in grid.horizontal.indices {
            var line: [Stone?] = []
            for column in grid.vertical.indices {
                let center = grid.intersection(row: row, column: column)
                // 书缝的阴影离这个点不到 0.35 格。
                let near = Int(grid.spacing * 0.35)
                let onShadow = (-near...near).contains { dy in (-near...near).contains { dx in shadows[Int(center.x) + dx, Int(center.y) + dy] } }
                let reading = StoneClassifier.classify(at: center, spacing: grid.spacing, ink: ink, ridges: ridges, onShadow: onShadow)
                let point = GridPoint(column: column, row: row)
                line.append(reading.stone)
                if reading.stone == .black { blacks[point] = darkness(at: center, spacing: grid.spacing, gray: gray) }
                if reading.uncertain { uncertain.insert(point) }
                if reading.marked {
                    marked[point] = CGPoint(x: center.x * scale, y: center.y * scale)
                    if GlyphReader.looksLikeOne(at: center, spacing: grid.spacing, ink: ink) { ones.insert(point) }
                }
            }
            stones.append(line)
        }
        let b = grid.bounds
        let diagram = RecognizedDiagram(
            id: id,
            number: nil,
            bounds: CGRect(x: b.minX * scale, y: b.minY * scale, width: (b.maxX - b.minX) * scale, height: (b.maxY - b.minY) * scale),
            columns: grid.vertical.count,
            rows: grid.horizontal.count,
            edges: grid.edges,
            stones: stones,
            labels: [:],
            uncertain: uncertain,
            markedStones: marked,
            oneShapedStones: ones,
            spacing: grid.spacing * scale
        )
        return (diagram, blacks)
    }

    /// 题号印在棋盘图左上方：找图左边、靠近图顶的数字，离图左上角最近的那个。
    private static func assignNumbers(to diagrams: inout [RecognizedDiagram], from text: [TextItem]) {
        let numbers = text.compactMap { item in TextReader.number(in: item.text).map { (value: $0, box: item.box) } }
        for index in diagrams.indices {
            let bounds = diagrams[index].bounds
            let candidates = numbers.filter { item in
                item.box.midX < bounds.minX + bounds.width * 0.1
                    && item.box.midX > bounds.minX - bounds.width * 0.5
                    && item.box.midY > bounds.minY - bounds.height * 0.2
                    && item.box.midY < bounds.minY + bounds.height * 0.4
            }
            let best = candidates.min { a, b in
                hypot(a.box.midX - bounds.minX, a.box.midY - bounds.minY) < hypot(b.box.midX - bounds.minX, b.box.midY - bounds.minY)
            }
            diagrams[index].number = best?.value
        }
    }

    /// 带圈的题号整页读时常常读不出来，把图左上方那一块单独裁出来再读一次。
    private static func readBadgeNumber(beside diagram: RecognizedDiagram, image: CGImage) -> Int? {
        let b = diagram.bounds
        let area = CGRect(x: b.minX - b.width * 0.45, y: b.minY - b.height * 0.1, width: b.width * 0.45, height: b.height * 0.4)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !area.isEmpty, let crop = PhotoLoader.crop(image, to: area),
              let items = try? TextReader.read(crop, minimumTextHeight: 0.05) else { return nil }
        return items.lazy.compactMap { TextReader.number(in: $0.text) }.first
    }

    /// 还有没读出题号的，按阅读顺序从读出来的题号往前往后推。读出来的题号互相对不上、又分不出哪个是读错的时候不推，免得推错。
    /// 题号按版面上的格子排：练习册一页是几行几列整齐排的，题号从左到右、从上到下数。
    /// 没认出来的图也占着一个格子，所以按格子算，而不是按认出来的图数。
    static func fillNumberSequence(_ diagrams: inout [RecognizedDiagram]) {
        let slots = layoutSlots(of: diagrams)
        // 先看前后：前后两道题的题号差和格子差一样，中间这道的题号就定了。没读出来的补上，
        // 读错的（比如 23 只读出 "3"）改过来。
        if diagrams.count >= 3 {
            for index in 1..<(diagrams.count - 1) {
                guard let before = diagrams[index - 1].number, let after = diagrams[index + 1].number,
                      after - before == slots[index + 1] - slots[index - 1] else { continue }
                diagrams[index].number = before + slots[index] - slots[index - 1]
            }
        }
        // 再看整页：读出来的题号大多是"格子号 + 同一个数"，没读出来的按这个补，对不上的改过来。
        // 带圈的两位数常常只读出一位（10 读成 "0"，19 读成 "1"），读出的是该有的题号的开头或结尾，也算对得上。
        // 读出来的都对得上；或者有两道一字不差、超过一半对得上，就按这个数补齐、改正。
        let reads = diagrams.indices.compactMap { index in diagrams[index].number.map { (slot: slots[index], value: $0) } }
        func agreement(_ offset: Int) -> (exact: Int, total: Int) {
            var exact = 0, total = 0
            for read in reads {
                let expected = String(read.slot + offset), value = String(read.value)
                if read.slot + offset == read.value { exact += 1; total += 1 }
                else if expected.hasPrefix(value) || expected.hasSuffix(value) { total += 1 }
            }
            return (exact, total)
        }
        let candidates = Set(reads.map { $0.value - $0.slot }).filter { $0 >= 1 }
        guard let offset = candidates.max(by: { a, b in
            let x = agreement(a), y = agreement(b)
            return (x.total, x.exact, -a) < (y.total, y.exact, -b)
        }) else { return }
        let (exact, total) = agreement(offset)
        guard total == reads.count || (exact >= 2 && total * 2 > reads.count) else { return }
        for index in diagrams.indices {
            diagrams[index].number = offset + slots[index]
        }
    }

    /// 每个图在版面上是第几格（从 0 数，一行一行数）。左边差不多齐的算同一列，上边差不多齐的算同一行。
    static func layoutSlots(of diagrams: [RecognizedDiagram]) -> [Int] {
        let widths: [Double] = diagrams.map { Double($0.bounds.width) }
        let heights: [Double] = diagrams.map { Double($0.bounds.height) }
        guard let width = median(widths), let height = median(heights) else { return [] }
        let columns = groupStarts(diagrams.map { Double($0.bounds.minX) }, tolerance: width / 2)
        let rows = groupStarts(diagrams.map { Double($0.bounds.minY) }, tolerance: height / 2)
        return diagrams.map { diagram in
            let row = groupIndex(of: Double(diagram.bounds.minY), in: rows)
            let column = groupIndex(of: Double(diagram.bounds.minX), in: columns)
            return row * columns.count + column
        }
    }

    /// 排好序以后，和前一组的起点差得比 tolerance 多就是新的一组，返回每组的起点。
    private static func groupStarts(_ values: [Double], tolerance: Double) -> [Double] {
        var starts: [Double] = []
        for value in values.sorted() {
            if let last = starts.last, value - last <= tolerance { continue }
            starts.append(value)
        }
        return starts
    }

    private static func groupIndex(of value: Double, in starts: [Double]) -> Int {
        var index = 0
        for (i, start) in starts.enumerated() where start <= value + 1 {
            index = i
        }
        return index
    }

    /// 同一页的图一般一样大。行数或列数比大多数图少，就是没拍全（被书缝、照片边挡住，或者反光看不清线）。
    /// 没拍全的从棋盘边那一侧量，补成大多数图的大小，缺的部分是空点，家长照着书补上。
    static func markIncomplete(_ diagrams: inout [RecognizedDiagram]) {
        guard diagrams.count >= 3 else { return }
        let columns = mostCommon(diagrams.map(\.columns)), rows = mostCommon(diagrams.map(\.rows))
        for index in diagrams.indices where diagrams[index].columns < columns || diagrams[index].rows < rows {
            diagrams[index].isIncomplete = true
            diagrams[index].pad(toColumns: columns, rows: rows)
        }
    }

    /// 出现最多的那个数，一样多时取大的。
    private static func mostCommon(_ values: [Int]) -> Int {
        let counts = Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.max { a, b in a.value == b.value ? a.key < b.key : a.value < b.value }?.key ?? 0
    }

    /// 页码在照片下面四分之一。圈在圆圈里的是题号（照片下面露出半截的下一道题），棋盘图里的是白子上的数字，都不是页码。
    private static func pageNumber(in text: [TextItem], imageHeight: Double, diagrams: [RecognizedDiagram], ink: InkMask, scale: Double) -> Int? {
        return text
            .filter { $0.box.minY > imageHeight * 0.75 && !isOnDiagram($0.box, diagrams) && !isInsideBadge($0.box, diagrams: diagrams, ink: ink, scale: scale) }
            .compactMap { TextReader.number(in: $0.text) }
            .first
    }

    /// 棋盘图上的字（白子上的数字）不是页码。
    private static func isOnDiagram(_ box: CGRect, _ diagrams: [RecognizedDiagram]) -> Bool {
        diagrams.contains { $0.bounds.contains(CGPoint(x: box.midX, y: box.midY)) }
    }

    private static func isInsideBadge(_ box: CGRect, diagrams: [RecognizedDiagram], ink: InkMask, scale: Double) -> Bool {
        guard let spacing = median(diagrams.map { $0.spacing / scale }) else { return false }
        let center = CGPoint(x: box.midX, y: box.midY)
        let area = box.insetBy(dx: -box.height * 1.5, dy: -box.height * 1.5)
        guard let badge = GlyphReader.findBadge(in: ink, area: area, spacing: spacing, scale: scale, near: center) else { return false }
        return hypot(badge.center.x - center.x, badge.center.y - center.y) < badge.radius
    }

    /// 棋子上的数字太小，整页读不出来。只把中间有墨迹的白子里面那块抠出来单独读；
    /// 读不出来、但墨迹是一道竖笔画的，当作"1"。
    private static func readLabels(on diagram: RecognizedDiagram, image: CGImage) -> [GridPoint: String] {
        var labels: [GridPoint: String] = [:]
        for (point, center) in diagram.markedStones {
            if let value = GlyphReader.number(in: image, center: center, radius: diagram.spacing * 0.36), value > 0 {
                labels[point] = String(value)
            } else if diagram.oneShapedStones.contains(point) {
                labels[point] = "1"
            }
        }
        return labels
    }

    /// 带圈的题号：在图的左边找到那个圆圈，把圈里的数字抠出来读。
    static func readRingedNumber(beside diagram: RecognizedDiagram, image: CGImage, ink: InkMask, scale: Double) -> Int? {
        let b = diagram.bounds
        let area = CGRect(x: b.minX - b.width * 0.45, y: b.minY - b.height * 0.1, width: b.width * 0.45, height: b.height * 0.4)
        guard let badge = GlyphReader.findBadge(in: ink, area: area, spacing: diagram.spacing / scale, scale: scale, near: CGPoint(x: b.minX, y: b.minY)) else {
            return nil
        }
        // 只取圆环里面的部分，圆环本身不要。
        return GlyphReader.number(in: image, center: badge.center, radius: badge.radius * 0.7)
    }

    /// 页码字小，整页读时常常漏掉。把照片最下面那一条单独裁出来再读。
    /// 不只看最低那个图的下面：只认出一半的图外框会往下伸，页码就在它旁边；图里面的字另外跳过。
    static func readPageNumberStrip(of image: CGImage, below diagrams: [RecognizedDiagram], ink: InkMask, scale: Double) -> Int? {
        let height = Double(image.height)
        let top = height * 0.8
        let width = Double(image.width)
        let strip = CGRect(x: 0, y: top, width: width, height: height - top).integral
        guard strip.height > 10 else { return nil }
        // 整条读不出来时，切成左中右三段再读（页码在角上或中间，旁边的书页边缘会干扰）。
        let pieces = [strip] + (0..<3).map { i in
            CGRect(x: width * Double(i) / 3, y: strip.minY, width: width / 3, height: strip.height)
        }
        for piece in pieces {
            guard let crop = PhotoLoader.crop(image, to: piece) else { continue }
            for fast in [false, true] {
                let items = (try? TextReader.read(crop, minimumTextHeight: 0, languages: ["en-US"], fast: fast)) ?? []
                let numbers = items.lazy
                    .filter { item in
                        let box = item.box.offsetBy(dx: piece.minX, dy: piece.minY)
                        return !isOnDiagram(box, diagrams) && !isInsideBadge(box, diagrams: diagrams, ink: ink, scale: scale)
                    }
                    .compactMap { TextReader.number(in: $0.text) }
                if let number = numbers.first { return number }
            }
        }
        return nil
    }
}
