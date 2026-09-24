import SwiftUI

struct ThemeColor {
    let ns: NSColor

    init(_ light: UInt32, _ dark: UInt32) {
        func make(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        let light = make(light)
        let dark = make(dark)
        ns = NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }

    var color: Color { Color(nsColor: ns) }
}

enum Theme {
    static let background = ThemeColor(0xF4F3EE, 0x262522)
    static let surface = ThemeColor(0xFFFFFF, 0x30302C)
    static let border = ThemeColor(0xE3E0D7, 0x3E3C37)
    static let text = ThemeColor(0x2C2B28, 0xECEAE3)
    static let secondary = ThemeColor(0x6F6C64, 0xA19E95)
    static let accent = ThemeColor(0xD97757, 0xD97757)
    static let onAccent = ThemeColor(0xFFFFFF, 0xFFFFFF)
    static let error = ThemeColor(0xB4382E, 0xE5756A)
}

struct PillButtonStyle: ButtonStyle {
    var prominent = true
    var small = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? .callout : .body.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, small ? 10 : 14)
            .padding(.vertical, small ? 3 : 6)
            .foregroundStyle(prominent ? Theme.onAccent.color : Theme.text.color)
            .background(prominent ? Theme.accent.color : Theme.surface.color, in: Capsule())
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Theme.border.color))
            .contentShape(Capsule())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}

struct Pills<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.title)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .foregroundStyle(selected ? Theme.onAccent.color : Theme.secondary.color)
                        .background(selected ? Theme.accent.color : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Theme.surface.color, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border.color))
    }
}

extension View {
    func card(radius: CGFloat = 12, padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.color, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Theme.border.color))
    }

    func themed(background: Bool = true) -> some View {
        self
            .foregroundStyle(Theme.text.color)
            .tint(Theme.accent.color)
            .focusEffectDisabled()
            .background(background ? Theme.background.color : Color.clear)
    }
}
