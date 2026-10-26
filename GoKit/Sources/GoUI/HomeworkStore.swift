import CoreGraphics
import Foundation
import GoCore
import ImageIO
import Observation
import UniformTypeIdentifiers

/// 作业本里的一道题。拍照来的题还带着作业纸上那道题的原图。
public struct SavedProblem: Codable, Identifiable, Hashable, Sendable {
    public var problem: Problem
    /// 第一次存进作业本的时间。校对后再存不改，按这个分到哪一天。
    public var saved: Date
    public var hasPhoto: Bool
    /// 识别时发现这道题没拍全。
    public var isIncomplete: Bool
    /// 作业纸上的页码和题号，拍照时读出来的才有。重拍同一页时用来认出是同一道题。
    /// 以前存的文件里没有这两项，读出来是 nil。
    public var page: Int?
    public var number: Int?
    /// 第一次用时放进来的例题，删不掉。以前存的例题文件里没有这一项，读出来是 nil，按题目名认。
    private var example: Bool?

    public var id: UUID { problem.id }

    /// 例题的题目名开头。
    static let examplePrefix = "例题："

    public var isExample: Bool {
        get { example ?? problem.title.hasPrefix(Self.examplePrefix) }
        set { example = newValue }
    }

    public init(problem: Problem, saved: Date = .now, hasPhoto: Bool = false, isIncomplete: Bool = false, page: Int? = nil, number: Int? = nil, isExample: Bool = false) {
        self.problem = problem
        self.saved = saved
        self.hasPhoto = hasPhoto
        self.isIncomplete = isIncomplete
        self.page = page
        self.number = number
        self.example = isExample
    }
}

/// 作业本：每道题一个 `<id>.json`，原图存成同名的 `.jpg`，都在本机，不上传。
@MainActor
@Observable
public final class HomeworkStore {
    /// 作业本列表的顺序：后存的在前，一页里最后一题在上。正好是“下一题”的顺序倒过来，见 `problem(after:)`。
    public private(set) var problems: [SavedProblem] = []
    private let directory: URL
    @ObservationIgnored private var photos: [UUID: CGImage] = [:]

    /// App 里用的位置：Application Support 下的“作业本”。
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "作业本", directoryHint: .isDirectory)
    }

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        // 读不了的文件（写到一半、版本不对）跳过，不让整个作业本打不开。
        problems = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(SavedProblem.self, from: $0) }
        sort()
    }

    public func contains(_ id: UUID) -> Bool {
        problems.contains { $0.id == id }
    }

    public subscript(id: UUID) -> SavedProblem? {
        problems.first { $0.id == id }
    }

    /// 做题时“下一题”做的那道。是最后存的那道、或者不在作业本里时没有。
    public func problem(after id: UUID) -> SavedProblem? {
        problem(id, offset: 1)
    }

    /// 做题时“上一题”做的那道。是最早存的那道、或者不在作业本里时没有。
    public func problem(before id: UUID) -> SavedProblem? {
        problem(id, offset: -1)
    }

    /// 上一题、下一题按做作业的先后：从最早存的往最晚存的，一页里按题号往下。
    /// 和列表正好反着：列表把新拍的放上面好找，做题还是按做作业的先后。
    private func problem(_ id: UUID, offset: Int) -> SavedProblem? {
        let order = problems.sorted { a, b in
            a.saved != b.saved ? a.saved < b.saved : Self.byTitle(a, b)
        }
        guard let index = order.firstIndex(where: { $0.id == id }), order.indices.contains(index + offset) else { return nil }
        return order[index + offset]
    }

    /// 作业本里同一页、同一题号的拍照题，重拍时拿新拍的换掉它。
    /// 以前存的文件没记页码和题号，就按自动起的题目名（“第 35 页第 7 题”）找。
    public func photoProblem(page: Int, number: Int, title: String) -> SavedProblem? {
        problems.first { saved in
            guard saved.hasPhoto else { return false }
            if let savedPage = saved.page, let savedNumber = saved.number { return savedPage == page && savedNumber == number }
            return saved.problem.title == title
        }
    }

    /// 存一道题，同一个 id 的覆盖。带 photo 时把原图也存下来。
    public func save(_ saved: SavedProblem, photo: CGImage? = nil) {
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: file(saved.id, "json"), options: .atomic)
        if let photo, let jpeg = Self.jpeg(photo) {
            try? jpeg.write(to: file(saved.id, "jpg"), options: .atomic)
            photos[saved.id] = photo
        }
        problems.removeAll { $0.id == saved.id }
        problems.append(saved)
        sort()
    }

    /// 第一次用时放一道例题进作业本。只放一次：以前的版本里例题能删，删掉了就不再放回来。
    public func addExampleOnce() {
        let marker = directory.appending(path: ".例题已放")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        var example = Problem.sample
        example.title = SavedProblem.examplePrefix + example.title
        save(SavedProblem(problem: example, isExample: true))
        FileManager.default.createFile(atPath: marker.path, contents: nil)
    }

    /// 能删的题：除了例题都能删。全选时选的就是这些。
    public var deletableIDs: Set<UUID> {
        Set(problems.filter { !$0.isExample }.map(\.id))
    }

    /// 删掉好几道题。混进来的例题不删。
    public func delete(_ ids: Set<UUID>) {
        for id in ids { delete(id) }
    }

    /// 删一道题。例题删不掉。
    public func delete(_ id: UUID) {
        guard self[id]?.isExample != true else { return }
        try? FileManager.default.removeItem(at: file(id, "json"))
        try? FileManager.default.removeItem(at: file(id, "jpg"))
        photos[id] = nil
        problems.removeAll { $0.id == id }
    }

    /// 这道题在作业纸上的原图。
    public func photo(for id: UUID) -> CGImage? {
        if let cached = photos[id] { return cached }
        guard self[id]?.hasPhoto == true,
              let source = CGImageSourceCreateWithURL(file(id, "jpg") as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        photos[id] = image
        return image
    }

    private func file(_ id: UUID, _ ext: String) -> URL {
        directory.appending(path: "\(id.uuidString).\(ext)")
    }

    /// 后存的在前，按天分组也就是新的一天在前。一页拍照存的题共用一个时间，同一时间按题目名倒着排，一页里第一题在最下面。
    /// 以前的版本一页的题按题号一道道存、各取各的时间，排出来也是这样。
    private func sort() {
        problems.sort { a, b in
            a.saved != b.saved ? a.saved > b.saved : Self.byTitle(b, a)
        }
    }

    /// 同一时间存的按题目名排，题号按数字大小（第 9 题在第 10 题前面）。
    private static func byTitle(_ a: SavedProblem, _ b: SavedProblem) -> Bool {
        a.problem.title.localizedStandardCompare(b.problem.title) == .orderedAscending
    }

    private static func jpeg(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
