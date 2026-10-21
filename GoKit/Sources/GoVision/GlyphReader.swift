import CoreGraphics
import Foundation

/// 读印在圆圈里的小数字：题号徽章、棋子上的手数。
/// 圆圈的轮廓和底色会干扰文字识别，所以先把圈里的字抠成白底黑字、放大，再交给文字识别。
enum GlyphReader {
    /// 读以 center 为圆心、radius 以内的数字。坐标是原照片的像素。
    /// 精确模式读不出单个数字时，快速模式（按字符认）常常能读出来，所以两种都试。
    static func number(in image: CGImage, center: CGPoint, radius: Double) -> Int? {
        guard let glyph = isolatedGlyph(in: image, center: center, radius: radius) else { return nil }
        for fast in [false, true] {
            guard let items = try? TextReader.read(glyph, minimumTextHeight: 0, languages: ["en-US"], fast: fast) else { continue }
            // 单独一个"1"常被读成字母 I 或 l。
            let value = items.lazy.compactMap { item in
                ["I", "l", "|", "i"].contains(item.text) ? 1 : TextReader.number(in: item.text)
            }.first
            if let value { return value }
        }
        return nil
    }

    /// 把圆内的字抠出来：比"最暗和中间亮度的平均"还暗的算字，画成黑色，其余都是白色；放大 4 倍，四周留白。
    /// 圆里没有明显比底色暗的东西就返回 nil。
    static func isolatedGlyph(in image: CGImage, center: CGPoint, radius: Double) -> CGImage? {
        let r = Int(radius.rounded(.up))
        let area = CGRect(x: Int(center.x) - r, y: Int(center.y) - r, width: 2 * r, height: 2 * r)
        guard r >= 3, let crop = PhotoLoader.crop(image, to: area), let gray = GrayImage(crop, maxDimension: 2 * r) else { return nil }

        var inside: [UInt8] = []
        for y in 0..<gray.height {
            for x in 0..<gray.width where hypot(Double(x) - Double(gray.width) / 2, Double(y) - Double(gray.height) / 2) <= radius {
                inside.append(gray[x, y])
            }
        }
        guard let darkest = inside.min() else { return nil }
        let middle = inside.sorted()[inside.count / 2]
        guard Int(middle) - Int(darkest) >= 40 else { return nil }
        let threshold = (Int(darkest) + Int(middle)) / 2

        let scale = 4, padding = 24
        let width = gray.width * scale + padding * 2, height = gray.height * scale + padding * 2
        var pixels = [UInt8](repeating: 255, count: width * height)
        for y in 0..<gray.height {
            for x in 0..<gray.width {
                let inCircle = hypot(Double(x) - Double(gray.width) / 2, Double(y) - Double(gray.height) / 2) <= radius
                guard inCircle, Int(gray[x, y]) < threshold else { continue }
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        pixels[(padding + y * scale + dy) * width + padding + x * scale + dx] = 0
                    }
                }
            }
        }
        return pixels.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )?.makeImage()
        }
    }

    /// 白子中间的墨迹是一道又高又窄的竖笔画，就当作"1"。文字识别在有些设备上读不出单独的"1"。
    static func looksLikeOne(at center: (x: Double, y: Double), spacing s: Double, ink: InkMask) -> Bool {
        let radius = s * 0.3
        let r = Int(radius.rounded(.up))
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for dy in -r...r {
            for dx in -r...r where Double(dx * dx + dy * dy) <= radius * radius {
                if ink[Int(center.x.rounded()) + dx, Int(center.y.rounded()) + dy] {
                    minX = min(minX, dx); maxX = max(maxX, dx)
                    minY = min(minY, dy); maxY = max(maxY, dy)
                }
            }
        }
        guard minX <= maxX else { return false }
        let width = Double(maxX - minX + 1), height = Double(maxY - minY + 1)
        return height >= s * 0.25 && height >= width * 1.8
    }

    /// 在 area 里找像一串数字的小团墨迹：每个字高度在 minHeight 到 maxHeight 之间、不太宽，
    /// 挨在一起、高低对齐的几个字合成一组。返回每组的外框（原照片像素）。
    static func textBlobs(in ink: InkMask, area: CGRect, scale: Double, minHeight: Double, maxHeight: Double) -> [CGRect] {
        let x0 = max(0, Int(area.minX / scale)), y0 = max(0, Int(area.minY / scale))
        let x1 = min(ink.width - 1, Int(area.maxX / scale)), y1 = min(ink.height - 1, Int(area.maxY / scale))
        guard x0 < x1, y0 < y1 else { return [] }
        let width = x1 - x0 + 1
        var seen = [Bool](repeating: false, count: width * (y1 - y0 + 1))
        var glyphs: [CGRect] = []
        for startY in y0...y1 {
            for startX in x0...x1 where ink[startX, startY] && !seen[(startY - y0) * width + startX - x0] {
                var stack = [(startX, startY)]
                seen[(startY - y0) * width + startX - x0] = true
                var minX = startX, maxX = startX, minY = startY, maxY = startY
                while let (x, y) = stack.popLast() {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                    where nx >= x0 && nx <= x1 && ny >= y0 && ny <= y1 && ink[nx, ny] && !seen[(ny - y0) * width + nx - x0] {
                        seen[(ny - y0) * width + nx - x0] = true
                        stack.append((nx, ny))
                    }
                }
                let w = Double(maxX - minX + 1), h = Double(maxY - minY + 1)
                if h >= minHeight && h <= maxHeight && w <= h * 1.5 {
                    glyphs.append(CGRect(x: minX, y: minY, width: Int(w), height: Int(h)))
                }
            }
        }

        // 从左到右，把高低对齐、间隔不到半个字高的字连成一组。
        var groups: [CGRect] = []
        for glyph in glyphs.sorted(by: { $0.minX < $1.minX }) {
            if let index = groups.lastIndex(where: { group in
                let overlap = min(group.maxY, glyph.maxY) - max(group.minY, glyph.minY)
                return overlap > glyph.height * 0.5 && glyph.minX - group.maxX < glyph.height * 0.6
            }) {
                groups[index] = groups[index].union(glyph)
            } else {
                groups.append(glyph)
            }
        }
        return groups.map { CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale) }
    }

    /// 在照片的 area 里找题号的圆圈：大小和棋子差不多、接近正方形、中间是空的（圆环）。
    /// 返回离 target 最近的那个圆的圆心和半径（原照片像素）。
    static func findBadge(in ink: InkMask, area: CGRect, spacing s: Double, scale: Double, near target: CGPoint) -> (center: CGPoint, radius: Double)? {
        let x0 = max(0, Int(area.minX / scale)), y0 = max(0, Int(area.minY / scale))
        let x1 = min(ink.width - 1, Int(area.maxX / scale)), y1 = min(ink.height - 1, Int(area.maxY / scale))
        guard x0 < x1, y0 < y1 else { return nil }
        let width = x1 - x0 + 1
        var seen = [Bool](repeating: false, count: width * (y1 - y0 + 1))
        var best: (center: CGPoint, radius: Double, distance: Double)?

        for startY in y0...y1 {
            for startX in x0...x1 where ink[startX, startY] && !seen[(startY - y0) * width + startX - x0] {
                var stack = [(startX, startY)]
                seen[(startY - y0) * width + startX - x0] = true
                var count = 0, minX = startX, maxX = startX, minY = startY, maxY = startY
                while let (x, y) = stack.popLast() {
                    count += 1
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    for (nx, ny) in [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                    where nx >= x0 && nx <= x1 && ny >= y0 && ny <= y1 && ink[nx, ny] && !seen[(ny - y0) * width + nx - x0] {
                        seen[(ny - y0) * width + nx - x0] = true
                        stack.append((nx, ny))
                    }
                }
                let w = Double(maxX - minX + 1), h = Double(maxY - minY + 1)
                let radius = (w + h) / 4
                let isRing = w >= s * 0.8 && w <= s * 2.5 && h / w > 0.8 && h / w < 1.25
                    && Double(count) / (Double.pi * radius * radius) < 0.6
                guard isRing else { continue }
                let center = CGPoint(x: (Double(minX + maxX) / 2) * scale, y: (Double(minY + maxY) / 2) * scale)
                let distance = hypot(center.x - target.x, center.y - target.y)
                if best == nil || distance < best!.distance {
                    best = (center, radius * scale, distance)
                }
            }
        }
        return best.map { ($0.center, $0.radius) }
    }
}
