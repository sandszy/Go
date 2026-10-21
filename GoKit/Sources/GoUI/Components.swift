import GoCore
import SwiftUI

/// 面板上用的小棋子图标。
struct StoneIcon: View {
    let stone: Stone
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(stone == .black ? Color.black : Color.white)
            .overlay(Circle().stroke(Color.gray, lineWidth: stone == .white ? 1 : 0))
            .frame(width: size, height: size)
    }
}

struct ToolIcon: View {
    let tool: SetupTool

    var body: some View {
        switch tool {
        case .black:
            StoneIcon(stone: .black)
        case .white:
            StoneIcon(stone: .white)
        case .alternate:
            HStack(spacing: -10) {
                StoneIcon(stone: .black)
                StoneIcon(stone: .white)
            }
        case .erase:
            Image(systemName: "eraser")
                .font(.system(size: 24))
        }
    }
}

/// 面板顶上的提示条：答对绿色，下错橙色，其他蓝色。
struct MessageBanner: View {
    let message: EditorMessage

    private var color: Color {
        switch message.tone {
        case .success: .green
        case .warning: .orange
        case .info: .blue
        }
    }

    var body: some View {
        Text(message.text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// 大按钮，孩子容易点中；选中时有边框和底色。
struct ToolButton<Icon: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    let icon: Icon

    init(title: String, selected: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.selected = selected
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        Button(action: action) {
            VStack(spacing: 6) {
                icon.frame(height: 30)
                Text(title).font(.callout.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(shape.fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
            .overlay(shape.stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
