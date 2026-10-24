import CoreGraphics
import Foundation
import GoCore
import GoUI
import SwiftUI

@main
struct DengDengGoApp: App {
    @State private var editor: ProblemEditorModel = {
        if ProcessInfo.processInfo.arguments.contains("-samplePhotoProblem") { return photoSampleEditor() }
        let homework = HomeworkStore(directory: HomeworkStore.defaultDirectory)
        homework.addExampleOnce()
        // 打开时是空棋盘；例题在作业本里。启动参数 `-sampleProblem` 直接摆上例题（UI 测试用）。
        let sample = ProcessInfo.processInfo.arguments.contains("-sampleProblem")
        return ProblemEditorModel(problem: sample ? .sample : Problem(), engine: InProcessKataGo.shared, homework: homework)
    }()

    init() {
        #if DEBUG
        EngineSelfTest.runIfRequested()
        #endif
    }

    /// UI 测试用（`-samplePhotoProblem`）：临时目录里的作业本放一道带原图、标着没拍全的例题，摆到棋盘上。
    /// 用来检查横屏时原图不用滚动就能看到（技术架构第 8 节）。不碰真的作业本。
    private static func photoSampleEditor() -> ProblemEditorModel {
        let homework = HomeworkStore(directory: FileManager.default.temporaryDirectory.appending(path: "UI测试作业本-\(UUID().uuidString)"))
        let saved = SavedProblem(problem: .sample, hasPhoto: true, isIncomplete: true, page: 35, number: 7)
        homework.save(saved, photo: samplePhoto())
        let editor = ProblemEditorModel(problem: Problem(), engine: InProcessKataGo.shared, homework: homework)
        editor.load(saved)
        return editor
    }

    /// 白底上画 9×9 的线，大小和比例跟作业纸上裁下来的一道题差不多。
    private static func samplePhoto() -> CGImage? {
        let size = 520
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 0.95, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setStrokeColor(CGColor(gray: 0.1, alpha: 1))
        context.setLineWidth(2)
        for i in 0..<9 {
            let position = CGFloat(40 + i * 55)
            context.strokeLineSegments(between: [CGPoint(x: position, y: 40), CGPoint(x: position, y: 480)])
            context.strokeLineSegments(between: [CGPoint(x: 40, y: position), CGPoint(x: 480, y: position)])
        }
        return context.makeImage()
    }

    var body: some Scene {
        WindowGroup {
            ProblemEditorView(model: editor)
        }
    }
}
