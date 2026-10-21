import SwiftUI

enum Theme {
    static let wood = Color(red: 0.87, green: 0.71, blue: 0.45)
    static let line = Color(red: 0.16, green: 0.11, blue: 0.06)

    static var background: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
}
