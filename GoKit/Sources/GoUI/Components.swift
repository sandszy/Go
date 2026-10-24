import GoCore
import SwiftUI

/// 面板上用的小棋子图标，和棋盘上的棋子用同一套质感。
struct StoneIcon: View {
    let stone: Stone
    var size: CGFloat = 28

    var body: some View {
        let light = UnitPoint(x: 0.32, y: 0.28)
        Circle()
            .fill(
                RadialGradient(
                    gradient: stone == .black ? Theme.blackStoneGradient : Theme.whiteStoneGradient,
                    center: light,
                    startRadius: 0,
                    endRadius: size * 0.75
                )
            )
            .overlay(Circle().stroke(stone == .black ? Theme.blackStoneRim.opacity(0.25) : Theme.whiteStoneRim, lineWidth: stone == .white ? 1 : 0.5))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: size * 0.08, x: size * 0.04, y: size * 0.06)
    }
}

struct ToolIcon: View {
    let tool: SetupTool

    var body: some View {
        switch tool {
        case .black:
            StoneIcon(stone: .black, size: 22)
        case .white:
            StoneIcon(stone: .white, size: 22)
        case .alternate:
            HStack(spacing: -8) {
                StoneIcon(stone: .black, size: 22)
                StoneIcon(stone: .white, size: 22)
            }
        case .erase:
            Image(systemName: "eraser")
                .font(.system(size: 18))
        case .cycle:
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 18))
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
        let shape = RoundedRectangle(cornerRadius: 10)
        Button(action: action) {
            VStack(spacing: 3) {
                icon.frame(height: 22)
                Text(title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(shape.fill(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05)))
            .overlay(shape.stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 摆题/做题：全局唯一的顶层选择，做成木纹底+铜色滑块，比面板里其它分段控件明显"重"一级、
/// 自带阴影浮起来，一眼能看出这块是单独的、更高一层的控件。
struct ModeSwitcherBar: View {
    let mode: EditorMode
    let onSelect: (EditorMode) -> Void

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EditorMode.allCases) { candidate in
                segment(candidate)
            }
        }
        .padding(5)
        .background(
            Capsule(style: .continuous)
                .fill(LinearGradient(gradient: Theme.modeBarGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.modeBarRim, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
    }

    private func segment(_ candidate: EditorMode) -> some View {
        let isSelected = candidate == mode
        return Button {
            guard !isSelected else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                onSelect(candidate)
            }
        } label: {
            Text(candidate.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(isSelected ? .white : Theme.line)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.gradient)
                            .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
                            .matchedGeometryEffect(id: "selectedMode", in: selection)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
