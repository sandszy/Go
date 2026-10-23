import GoCore
import GoUI
import SwiftUI

@main
struct DengDengGoApp: App {
    @State private var editor: ProblemEditorModel = {
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

    var body: some Scene {
        WindowGroup {
            ProblemEditorView(model: editor)
        }
    }
}
