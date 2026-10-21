import GoUI
import SwiftUI

@main
struct DengDengGoApp: App {
    @State private var editor = ProblemEditorModel(engine: InProcessKataGo.shared)

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
