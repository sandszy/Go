import CoreGraphics
import Foundation
import ImageIO

/// 灰度图，一个字节一个像素，0 是黑、255 是白。原点在左上角。
struct GrayImage {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// 缩放到长边不超过 maxDimension 再转灰度。
    init?(_ image: CGImage, maxDimension: Int) {
        let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, pixels: pixels)
    }

    subscript(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }

    /// 按局部亮度找墨迹：比周围 window×window 范围的平均亮度暗 ratio 以上的点算墨迹。
    /// 阴影里纸和墨都变暗，比例不变，所以不怕阴影。window 要比棋子大，否则黑子中间会被当成纸。
    func inkMask(window: Int, ratio: Double) -> InkMask {
        // 积分图：sum[y][x] 是左上角到 (x-1, y-1) 的亮度和。
        let stride = width + 1
        var integral = [Int](repeating: 0, count: stride * (height + 1))
        for y in 0..<height {
            var rowSum = 0
            for x in 0..<width {
                rowSum += Int(pixels[y * width + x])
                integral[(y + 1) * stride + x + 1] = integral[y * stride + x + 1] + rowSum
            }
        }
        let half = window / 2
        var ink = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            let y0 = max(0, y - half), y1 = min(height, y + half + 1)
            for x in 0..<width {
                let x0 = max(0, x - half), x1 = min(width, x + half + 1)
                let sum = integral[y1 * stride + x1] - integral[y0 * stride + x1] - integral[y1 * stride + x0] + integral[y0 * stride + x0]
                let mean = Double(sum) / Double((x1 - x0) * (y1 - y0))
                ink[y * width + x] = Double(pixels[y * width + x]) < mean * ratio
            }
        }
        return InkMask(width: width, height: height, bits: ink)
    }
}

extension GrayImage {
    /// 线点：比两侧 distance 像素处都暗——亮度不到两侧较暗那一侧的 ratio，并且至少暗 contrast 级灰度。
    /// 横线看上下两侧，竖线看左右两侧。线糊成浅灰的宽带也还是比两侧暗；灰底框的边一侧暗一侧亮，不算。
    /// 要求暗出 contrast 级，是为了不把深色桌面、照片边上暗处的纹理当成线。
    func ridges(distance d: Int, ratio: Double = 0.85, contrast: Double = 25) -> (horizontal: InkMask, vertical: InkMask) {
        var horizontal = [Bool](repeating: false, count: width * height)
        var vertical = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let value = Double(pixels[y * width + x])
                if y >= d && y + d < height {
                    let side = Double(min(pixels[(y - d) * width + x], pixels[(y + d) * width + x]))
                    horizontal[y * width + x] = value < side * ratio && side - value >= contrast
                }
                if x >= d && x + d < width {
                    let side = Double(min(pixels[y * width + x - d], pixels[y * width + x + d]))
                    vertical[y * width + x] = value < side * ratio && side - value >= contrast
                }
            }
        }
        return (InkMask(width: width, height: height, bits: horizontal), InkMask(width: width, height: height, bits: vertical))
    }
}

/// 每个像素是不是墨迹。越界当作纸。
struct InkMask {
    let width: Int
    let height: Int
    var bits: [Bool]

    subscript(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return bits[y * width + x]
    }

    /// 照片拍歪了、纸页弯了，棋盘线就不是正横正竖的。除了正横正竖，再沿这些斜率扫，
    /// 斜着的线总有一个斜率跟它差不多，能扫出够长的一段。
    static let scanSlopes: [Double] = [-0.1, -0.08, -0.06, -0.04, -0.02, 0, 0.02, 0.04, 0.06, 0.08, 0.1]

    /// 只留下细的横线：线点图 ridges.along 上的点（比上下两侧都暗），连续长度够长。黑子内部、文字笔画不是线点，会被去掉。
    /// 和竖线交叉的地方不一定是线点，这种墨迹（本身是墨，或者是竖线的线点）不超过 gap + 2 像素的短暂中断可以跨过去；
    /// 黑子太宽，跨不过去。沿 scanSlopes 里的每个斜率各扫一遍（y = 起点 + 斜率 × x），合起来。
    /// 一遍扫出两张图：不短于 minLengths.long 的长线（找棋盘图用），不短于 minLengths.short 的短线（定每条线的位置用）。
    func thinHorizontalRuns(minLengths: (short: Int, long: Int), gap: Int, ridges: (along: InkMask, across: InkMask)) -> (short: InkMask, long: InkMask) {
        var short = [Bool](repeating: false, count: width * height)
        var long = [Bool](repeating: false, count: width * height)
        for slope in Self.scanSlopes {
            let reach = Int((abs(slope) * Double(width)).rounded(.up))
            for start in -reach..<(height + reach) {
                func y(_ x: Int) -> Int { start + Int((slope * Double(x)).rounded()) }
                scanRun(length: width, minLength: minLengths.short, bridge: gap + 2) { x in
                    let y = y(x)
                    if ridges.along[x, y] { return true }
                    return self[x, y] || ridges.across[x, y] ? false : nil
                } mark: { x, runLength in
                    let y = y(x)
                    guard y >= 0 && y < height else { return }
                    short[y * width + x] = true
                    if runLength >= minLengths.long { long[y * width + x] = true }
                }
            }
        }
        return (InkMask(width: width, height: height, bits: short), InkMask(width: width, height: height, bits: long))
    }

    /// 只留下细的竖线，和 thinHorizontalRuns 对称。
    func thinVerticalRuns(minLengths: (short: Int, long: Int), gap: Int, ridges: (along: InkMask, across: InkMask)) -> (short: InkMask, long: InkMask) {
        var short = [Bool](repeating: false, count: width * height)
        var long = [Bool](repeating: false, count: width * height)
        for slope in Self.scanSlopes {
            let reach = Int((abs(slope) * Double(height)).rounded(.up))
            for start in -reach..<(width + reach) {
                func x(_ y: Int) -> Int { start + Int((slope * Double(y)).rounded()) }
                scanRun(length: height, minLength: minLengths.short, bridge: gap + 2) { y in
                    let x = x(y)
                    if ridges.along[x, y] { return true }
                    return self[x, y] || ridges.across[x, y] ? false : nil
                } mark: { y, runLength in
                    let x = x(y)
                    guard x >= 0 && x < width else { return }
                    short[y * width + x] = true
                    if runLength >= minLengths.long { long[y * width + x] = true }
                }
            }
        }
        return (InkMask(width: width, height: height, bits: short), InkMask(width: width, height: height, bits: long))
    }

    /// 沿一行（或一列）扫描。thin 返回 nil 表示纸，true 表示细线上的墨迹，false 表示墨迹但不细。
    /// 不细的墨迹连续不超过 bridge 个可以跨过；不短于 minLength 的一段细线整段标记，同时告诉这段有多长。
    private func scanRun(length: Int, minLength: Int, bridge: Int, thin: (Int) -> Bool?, mark: (Int, Int) -> Void) {
        var start = -1, lastThin = -1, notThin = 0
        func finish() {
            if start >= 0, lastThin - start + 1 >= minLength {
                for i in start...lastThin { mark(i, lastThin - start + 1) }
            }
            start = -1
            notThin = 0
        }
        for i in 0..<length {
            switch thin(i) {
            case true?:
                if start < 0 { start = i }
                lastThin = i
                notThin = 0
            case false? where start >= 0 && notThin < bridge:
                notThin += 1
            default:
                finish()
            }
        }
        finish()
    }

    /// 每个墨点往四周扩 radius 像素（正方形）。
    func dilated(by radius: Int) -> InkMask {
        var rows = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            var last = -radius - 1
            for x in 0..<min(width, radius) where bits[y * width + x] { last = x }
            for x in 0..<width {
                if x + radius < width && bits[y * width + x + radius] { last = x + radius }
                if last >= x - radius { rows[y * width + x] = true }
            }
        }
        var result = [Bool](repeating: false, count: width * height)
        for x in 0..<width {
            var last = -radius - 1
            for y in 0..<min(height, radius) where rows[y * width + x] { last = y }
            for y in 0..<height {
                if y + radius < height && rows[(y + radius) * width + x] { last = y + radius }
                if last >= y - radius { result[y * width + x] = true }
            }
        }
        return InkMask(width: width, height: height, bits: result)
    }

    func subtracting(_ other: InkMask) -> InkMask {
        InkMask(width: width, height: height, bits: zip(bits, other.bits).map { $0 && !$1 })
    }

    func union(_ other: InkMask) -> InkMask {
        InkMask(width: width, height: height, bits: zip(bits, other.bits).map { $0 || $1 })
    }
}

/// 读入照片并按 EXIF 方向转正。HEIC、JPEG、PNG 都行。
public enum PhotoLoader {
    public static func image(from data: Data, maxDimension: Int = 2400) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return orientedImage(from: source, maxDimension: maxDimension)
    }

    public static func image(at url: URL, maxDimension: Int = 2400) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return orientedImage(from: source, maxDimension: maxDimension)
    }

    /// 裁出 rect 这一块（像素，原点在左上角）。
    /// 不用 CGImage.cropping：iOS 上从照片解码出来的图，cropping 有时取到错位、带乱码的像素，所以重新画一张。
    public static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let area = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard area.width >= 1, area.height >= 1,
              let context = CGContext(
                  data: nil, width: Int(area.width), height: Int(area.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }
        // CGContext 的原点在左下角，把整张图挪过去，让要的那块正好落在画布上。
        context.draw(image, in: CGRect(
            x: -area.minX,
            y: area.maxY - CGFloat(image.height),
            width: CGFloat(image.width),
            height: CGFloat(image.height)
        ))
        return context.makeImage()
    }

    private static func orientedImage(from source: CGImageSource, maxDimension: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
