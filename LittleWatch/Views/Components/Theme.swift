import SwiftUI

enum LittleWatchTheme {
    static let canvas = Color(red: 0.055, green: 0.060, blue: 0.068)
    static let sidebar = Color(red: 0.040, green: 0.044, blue: 0.050)
    static let surface = Color.white.opacity(0.055)
    static let raisedSurface = Color.white.opacity(0.085)
    static let hairline = Color.white.opacity(0.10)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.54)
    static let signal = Color(red: 0.69, green: 0.94, blue: 0.43)
    static let amber = Color(red: 1.00, green: 0.70, blue: 0.30)
    static let cyan = Color(red: 0.38, green: 0.80, blue: 0.92)
}

struct InstrumentCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LittleWatchTheme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(LittleWatchTheme.hairline, lineWidth: 1)
                    }
            )
    }
}

extension View {
    func instrumentCard() -> some View {
        modifier(InstrumentCardModifier())
    }
}
