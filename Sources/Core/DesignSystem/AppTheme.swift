import SwiftUI
import UIKit

enum AppTheme {
    static let canvas = Color(uiColor: .secondarySystemBackground)
    static let canvasAlt = Color(uiColor: .secondarySystemBackground)
    static let card = Color(uiColor: .systemBackground)
    static let cardStrong = Color(uiColor: .systemBackground)
    static let cardStroke = Color(uiColor: .separator).opacity(0.22)
    static let ink = Color(uiColor: .label)
    static let muted = Color(uiColor: .secondaryLabel)
    static let faintText = Color(uiColor: .tertiaryLabel)

    static let accent = Color(uiColor: .systemTeal)
    static let accentDeep = Color(uiColor: .systemIndigo)
    static let accentSoft = Color(uiColor: .systemTeal).opacity(0.14)

    static let lavender = Color(uiColor: .systemPurple).opacity(0.22)
    static let sky = Color(uiColor: .systemBlue).opacity(0.20)
    static let butter = Color(uiColor: .systemYellow).opacity(0.22)
    static let coral = Color(uiColor: .systemOrange).opacity(0.22)

    static let success = Color(uiColor: .systemGreen)
    static let warning = Color(uiColor: .systemOrange)
    static let error = Color(uiColor: .systemRed)

    static let pageGradient = LinearGradient(
        colors: [
            canvas,
            canvas,
            canvasAlt
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGradient = LinearGradient(
        colors: [
            Color(uiColor: .systemBackground),
            Color(uiColor: .secondarySystemBackground)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func categoryColor(_ category: String) -> Color {
        switch category {
        case "Food": return Color(uiColor: .systemOrange)
        case "Groceries": return Color(uiColor: .systemGreen)
        case "Transport": return Color(uiColor: .systemBlue)
        case "Transportation": return Color(uiColor: .systemBlue)
        case "Entertainment": return Color(uiColor: .systemPurple)
        case "Shopping": return Color(uiColor: .systemPink)
        case "Bills": return Color(uiColor: .systemRed)
        case "Utilities": return Color(uiColor: .systemRed)
        case "Housing": return Color(uiColor: .systemIndigo)
        case "Health", "Medical": return Color(uiColor: .systemTeal)
        case "Education": return Color(uiColor: .systemYellow)
        case "Work", "Business": return Color(uiColor: .systemBlue)
        case "Subscriptions": return Color(uiColor: .systemIndigo)
        case "ATM": return Color(uiColor: .systemMint)
        default: return Color(uiColor: .systemGray)
        }
    }
}

struct AppCanvasBackground: View {
    var body: some View {
        AppTheme.canvas
            .ignoresSafeArea()
    }
}

struct SpeakCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 24
    var fill: AnyShapeStyle = AnyShapeStyle(AppTheme.card)
    var stroke: Color = AppTheme.cardStroke
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(AppTheme.cardStrong)
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(fill)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 8, y: 2)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.faintText)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.cardStrong, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                    )
            }
        }
    }
}

struct MetricChip: View {
    let title: String
    let value: String
    var tint: Color = AppTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.faintText)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ModernTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.20), lineWidth: 1)
            )
    }
}

extension View {
    func modernField() -> some View {
        modifier(ModernTextFieldStyle())
    }
}

enum CurrencyFormatter {
    private static var formatters: [String: NumberFormatter] = [:]
    private static let lock = NSLock()

    static func string(
        _ amount: Decimal,
        currency: String = "USD",
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 2
    ) -> String {
        lock.lock()
        defer { lock.unlock() }
        let formatter = formatterFor(
            currency: currency,
            minimumFractionDigits: minimumFractionDigits,
            maximumFractionDigits: maximumFractionDigits
        )
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount)"
    }

    private static func formatterFor(
        currency: String,
        minimumFractionDigits: Int,
        maximumFractionDigits: Int
    ) -> NumberFormatter {
        let key = "\(currency)|\(minimumFractionDigits)|\(maximumFractionDigits)"

        if let existing = formatters[key] {
            return existing
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatters[key] = formatter
        return formatter
    }
}
