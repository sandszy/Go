import CoreGraphics
import Foundation
import Vision

/// 照片转了方向时按页面上文字的方向转正。平放拍书时手机常常判错方向，照片自带的方向信息靠不住；
/// 作业页上总有标题、说明、题号这些字，系统文字识别能读出倒着、横着的字，还会给出每行字从左到右的走向。
public enum PageOrientation {
    /// 判方向用的小图的长边。字够大，读一遍只要零点几秒。
    static let checkSize = 1200

    /// 照片要顺时针转几个 90° 才是正的（0 到 3）。读出的字太少、或者各个方向的字差不多多时不转。
    static func quarterTurns(of image: CGImage) -> Int {
        guard let small = redraw(image, maxDimension: checkSize, quarterTurns: 0) else { return 0 }
        let request = VNRecognizeTextRequest()
        // 快速模式不认中文，只能用精确模式。
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: small).perform([request])) != nil else { return 0 }

        // 每行字按字数给它走向的那个方向投票。Vision 的坐标原点在左下角，y 朝上。
        var votes = [0, 0, 0, 0]
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first?.string, text.count >= 2 else { continue }
            let dx = observation.topRight.x - observation.topLeft.x
            let dy = observation.topRight.y - observation.topLeft.y
            let turns: Int
            if abs(dx) >= abs(dy) {
                // 朝右是正的；朝左是倒过来了，转 180°。
                turns = dx > 0 ? 0 : 2
            } else {
                // 字从下往上走：照片被逆时针转了 90°，顺时针转回来；从上往下走就反过来。
                turns = dy > 0 ? 1 : 3
            }
            votes[turns] += text.count
        }
        let total = votes.reduce(0, +)
        guard total >= 4, let best = votes.indices.max(by: { votes[$0] < votes[$1] }),
              Double(votes[best]) > Double(total) * 0.6 else { return 0 }
        return best
    }

    /// 转正以后的照片。本来就是正的、或者看不出方向时原样返回。
    public static func upright(_ image: CGImage) -> CGImage {
        let turns = quarterTurns(of: image)
        guard turns != 0 else { return image }
        return redraw(image, maxDimension: max(image.width, image.height), quarterTurns: turns) ?? image
    }

    /// 缩到长边不超过 maxDimension，再顺时针转 quarterTurns 个 90° 重画一张。
    static func redraw(_ image: CGImage, maxDimension: Int, quarterTurns: Int) -> CGImage? {
        let scale = min(1, Double(maxDimension) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        let turned = quarterTurns % 2 == 1
        guard let context = CGContext(
            data: nil, width: turned ? height : width, height: turned ? width : height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        // CGContext 的 y 朝上，正角度是逆时针，所以顺时针转要用负角度。
        context.translateBy(x: CGFloat(context.width) / 2, y: CGFloat(context.height) / 2)
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        context.draw(image, in: CGRect(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }
}
