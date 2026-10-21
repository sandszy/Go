import GoUI
import SwiftUI

@main
struct DengDengGoApp: App {
    @State private var editor = ProblemEditorModel()

    var body: some Scene {
        WindowGroup {
            ProblemEditorView(model: editor)
        }
    }
}
