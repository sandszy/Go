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
        let toOriginal = Double(image.width) / Double(gray.width)

        var diagrams = GridDetector.detect(in: ink).enumerated().map { index, grid in
            makeDiagram(id: index, grid: grid, ink: ink, scale: toOriginal)
        }

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
        for index in diagrams.indices {
            diagrams[index].labels = readLabels(on: diagrams[index], image: image)
        }

        return RecognizedPage(
            imageSize: CGSize(width: image.width, height: image.height),
            diagrams: diagrams,
            toPlay: TextReader.toPlay(in: text),
            goal: TextReader.goal(in: text),
            pageNumber: pageNumber(in: text, imageHeight: Double(image.height), diagrams: diagrams)
                ?? readPageNumberStrip(of: image, below: diagrams)
                ?? readPageNumberBlobs(of: image, below: diagrams, ink: ink, scale: toOriginal)
        )
    }

    /// 页码条整条读不出来时（小字在大片空白里，有的设备上找不到），先找出像数字的那一小团墨迹，只裁那一块读。
    private static func readPageNumberBlobs(of image: CGImage, below diagrams: [RecognizedDiagram], ink: InkMask, scale: Double) -> Int? {
        guard let spacing = median(diagrams.map { $0.spacing / scale }) else { return nil }
        let height = Double(image.height)
        let top = max(diagrams.map(\.bounds.maxY).max() ?? 0, height * 0.8)
        let strip = CGRect(x: 0, y: top, width: Double(image.width), height: height - top)
        let blobs = GlyphReader.textBlobs(in: ink, area: strip, scale: scale, minHeight: spacing * 0.3, maxHeight: spacing * 1.2)
        for blob in blobs {
            let padded = blob.insetBy(dx: -blob.height * 0.6, dy: -blob.height * 0.6)
            guard let crop = PhotoLoader.crop(image, to: padded) else { continue }
            for fast in [false, true] {
                let items = (try? TextReader.read(crop, minimumTextHeight: 0, languages: ["en-US"], fast: fast)) ?? []
                if let number = items.lazy.compactMap({ TextReader.number(in: $0.text) }).first { return number }
            }
        }
        return nil
    }

    private static func makeDiagram(id: Int, grid: DetectedGrid, ink: InkMask, scale: Double) -> RecognizedDiagram {
        var stones: [[Stone?]] = []
        var uncertain = Set<GridPoint>()
        var marked: [GridPoint: CGPoint] = [:]
        var ones = Set<GridPoint>()
        for row in grid.horizontal.indices {
            var line: [Stone?] = []
            for column in grid.vertical.indices {
                let center = grid.intersection(row: row, column: column)
                let reading = StoneClassifier.classify(at: center, spacing: grid.spacing, ink: ink)
                let point = GridPoint(column: column, row: row)
                line.append(reading.stone)
                if reading.uncertain { uncertain.insert(point) }
                if reading.marked {
                    marked[point] = CGPoint(x: center.x * scale, y: center.y * scale)
                    if GlyphReader.looksLikeOne(at: center, spacing: grid.spacing, ink: ink) { ones.insert(point) }
                }
            }
            stones.append(line)
        }
        let b = grid.bounds
        return RecognizedDiagram(
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

    /// 还有没读出题号的，按阅读顺序从读出来的题号往前往后推。几个读出来的题号对不上时就不推，免得推错。
    private static func fillNumberSequence(_ diagrams: inout [RecognizedDiagram]) {
        let offsets = Set(diagrams.enumerated().compactMap { index, diagram in diagram.number.map { $0 - index } })
        guard offsets.count == 1, let offset = offsets.first, offset + 0 >= 1 else { return }
        for index in diagrams.indices where diagrams[index].number == nil {
            diagrams[index].number = offset + index
        }
    }

    /// 页码印在页面最下面，不是题号。
    private static func pageNumber(in text: [TextItem], imageHeight: Double, diagrams: [RecognizedDiagram]) -> Int? {
        let lowest = diagrams.map(\.bounds.maxY).max() ?? 0
        return text
            .filter { $0.box.minY > max(lowest, imageHeight * 0.75) }
            .compactMap { TextReader.number(in: $0.text) }
            .first
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

    /// 页码字小，整页读时常常漏掉。把最后一个棋盘图下面那一条单独裁出来再读。
    static func readPageNumberStrip(of image: CGImage, below diagrams: [RecognizedDiagram]) -> Int? {
        let height = Double(image.height)
        let top = max(diagrams.map(\.bounds.maxY).max() ?? 0, height * 0.8)
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
                if let number = items.lazy.compactMap({ TextReader.number(in: $0.text) }).first { return number }
            }
        }
        return nil
    }
}
