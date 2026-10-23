import CoreGraphics
import Foundation
import GoCore
import Vision

/// 照片上的一段文字和它的位置（像素，原点在左上角）。
struct TextItem {
    var text: String
    var box: CGRect
}

/// 用系统的文字识别读页面上的字。
enum TextReader {
    static func read(
        _ image: CGImage,
        minimumTextHeight: Float = 0.01,
        languages: [String] = ["zh-Hans", "en-US"],
        fast: Bool = false
    ) throws -> [TextItem] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.recognitionLanguages = languages
        // 题号、页码都是单独的数字，语言校正会把它们改掉。
        request.usesLanguageCorrection = false
        request.minimumTextHeight = minimumTextHeight
        try VNImageRequestHandler(cgImage: image).perform([request])

        let width = Double(image.width), height = Double(image.height)
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let b = observation.boundingBox
            let box = CGRect(x: b.minX * width, y: (1 - b.maxY) * height, width: b.width * width, height: b.height * height)
            return TextItem(text: text, box: box)
        }
    }

    /// 页面上写的是黑先还是白先。
    static func toPlay(in items: [TextItem]) -> Stone? {
        let all = items.map(\.text).joined()
        if all.contains("白先") { return .white }
        if all.contains("黑先") { return .black }
        return nil
    }

    /// 从标题和说明里的关键词猜题目类型。"对杀"要先于"杀"判断。
    /// 作业纸上的七种题型按外框的摆法归成三种：做活和吃子一样，杀棋和逃子一样，连接、切断和对杀一样。
    static func goal(in items: [TextItem]) -> ProblemGoal? {
        let all = items.map(\.text).joined()
        let keywords: [(String, ProblemGoal)] = [
            ("对杀", .capturingRace),
            ("做活", .capture),
            ("杀", .escape),
            ("逃", .escape),
            ("征", .capture), ("枷", .capture), ("吃", .capture), ("提", .capture),
            ("连接", .capturingRace), ("切断", .capturingRace),
        ]
        return keywords.first { all.contains($0.0) }?.1
    }

    /// 纯数字，或者带圈的数字（①到⑳）。
    static func number(in text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let scalar = trimmed.unicodeScalars.first, trimmed.unicodeScalars.count == 1,
           (0x2460...0x2473).contains(scalar.value) {
            return Int(scalar.value - 0x2460 + 1)
        }
        guard !trimmed.isEmpty, trimmed.count <= 3, trimmed.allSatisfy(\.isASCII), let value = Int(trimmed) else { return nil }
        return value
    }
}
