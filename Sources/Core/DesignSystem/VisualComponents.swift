import SwiftUI

struct AudioPulseRings: View {
    let isActive: Bool
    var color: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { idx in
                    let phase = t + Double(idx) * 0.35
                    let dynamic = reduceMotion ? 0 : 0.11 * sin(phase * 3.2)
                    let scale = isActive ? (1.0 + dynamic) : (0.96 + Double(idx) * 0.03)
                    let opacity = isActive ? (0.20 - Double(idx) * 0.04) : 0.08

                    Circle()
                        .stroke(color.opacity(opacity), lineWidth: 1.5)
                        .scaleEffect(scale + Double(idx) * 0.08)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct MiniWaveform: View {
    let isActive: Bool
    var color: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<18, id: \.self) { idx in
                    let base = CGFloat((idx % 5) + 1) * 5
                    let dynamic = reduceMotion ? 0 : CGFloat(abs(sin(t * 4.2 + Double(idx) * 0.55))) * 18
                    let height = isActive ? max(8, base + dynamic) : (8 + CGFloat(idx % 3) * 3)

                    Capsule()
                        .fill(color.opacity(isActive ? 0.85 : 0.35))
                        .frame(width: 4, height: height)
                }
            }
            .frame(height: 32)
        }
    }
}

struct CategoryDot: View {
    let category: String

    var body: some View {
        Circle()
            .fill(AppTheme.categoryColor(category))
            .frame(width: 10, height: 10)
    }
}

struct SegmentedPill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? AppTheme.ink : AppTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(AppTheme.cardStrong, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(uiColor: .separator).opacity(isSelected ? 0.18 : 0.12), lineWidth: 1)
            )
    }
}
