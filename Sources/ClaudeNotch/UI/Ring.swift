import SwiftUI

struct Ring: View {
    var fraction: Double            // 0...1 elapsed
    var state: RingState
    var lineWidth: CGFloat = 4

    private var color: Color {
        switch state {
        case .ok: return Palette.accent
        case .warn: return Palette.amber
        case .critical: return Palette.red
        }
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(color, style: .init(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: fraction)
        }
    }
}
