import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTripID: UUID?
    @State private var selectedPaymentMethodID: UUID?

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    filtersCard
                    donutCard
                    summaryRow
                    categoryBreakdownCard
                }
                .padding(.horizontal, 16)
                .padding(.top, max(10, proxy.safeAreaInsets.top + 6))
                .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 8))
            }
            .background(AppCanvasBackground())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var scopedExpenses: [ExpenseRecord] {
        store.filteredExpenses(tripID: selectedTripID, paymentMethodID: selectedPaymentMethodID)
    }

    private var scopedCategoryTotals: [(String, Decimal)] {
        store.categoryTotals(tripID: selectedTripID, paymentMethodID: selectedPaymentMethodID)
    }

    private var scopedTotal: Decimal {
        scopedExpenses.reduce(.zero) { $0 + $1.amount }
    }

    private var donutSegments: [DonutSegment] {
        let total = NSDecimalNumber(decimal: scopedTotal).doubleValue
        guard total > 0 else { return [] }

        let maxSegments = 5
        let sorted = scopedCategoryTotals
        let top = Array(sorted.prefix(maxSegments))
        let remaining = sorted.dropFirst(maxSegments).reduce(Decimal.zero) { $0 + $1.1 }

        var source: [(String, Decimal)] = top
        if remaining > 0 {
            source.append(("More", remaining))
        }

        return source.map { category, value in
            let doubleValue = NSDecimalNumber(decimal: value).doubleValue
            return DonutSegment(
                category: category,
                amount: value,
                ratio: max(0, min(1, doubleValue / total)),
                color: category == "More" ? Color(uiColor: .systemGray4) : AppTheme.categoryColor(category)
            )
        }
    }

    private var headerCard: some View {
        SpeakCard(padding: 18, cornerRadius: 28, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Insights")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Your spending, visually organized.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    StatusPill(
                        text: store.isConnected ? "Synced" : "Offline",
                        color: store.isConnected ? AppTheme.success : AppTheme.warning
                    )
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedTripID == nil ? "Total spend" : "Trip spend")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.faintText)
                        Text(insightsCurrencyString(scopedTotal))
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Top category")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.faintText)
                        HStack(spacing: 6) {
                            CategoryDot(category: topCategoryName)
                            Text(topCategoryName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.ink)
                        }
                    }
                }
            }
        }
    }

    private var filtersCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Filters", subtitle: "Trip and payment method")

                Menu {
                    Button("All Trips") { selectedTripID = nil }
                    ForEach(store.activeTripFilterOptions) { trip in
                        Button(trip.name) { selectedTripID = trip.id }
                    }
                } label: {
                    filterRow(title: "Trip", value: selectedTripName)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("All Payment Methods") { selectedPaymentMethodID = nil }
                    ForEach(store.activePaymentMethodOptions) { method in
                        Button(method.name) { selectedPaymentMethodID = method.id }
                    }
                } label: {
                    filterRow(title: "Payment Method", value: selectedPaymentName)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func filterRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.muted)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(AppTheme.faintText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(AppTheme.cardStrong)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var donutCard: some View {
        SpeakCard(padding: 18, cornerRadius: 24, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(
                    title: "Spending Mix",
                    subtitle: selectedTripID == nil ? "Category share for current filters" : "Category share for active filters"
                )

                if donutSegments.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No data yet")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Text("Add a few expenses and your category donut will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center, spacing: 18) {
                            DonutChartView(
                                segments: donutSegments,
                                centerTitle: insightsCurrencyString(scopedTotal),
                                centerSubtitle: "\(scopedExpenses.count) entries"
                            )
                            .frame(width: 190, height: 190)
                            .padding(.vertical, 8)

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(donutSegments.prefix(5))) { segment in
                                    legendRow(segment)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)

                        VStack(alignment: .leading, spacing: 14) {
                            DonutChartView(
                                segments: donutSegments,
                                centerTitle: insightsCurrencyString(scopedTotal),
                                centerSubtitle: "\(scopedExpenses.count) entries"
                            )
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: 220)
                            .padding(.vertical, 10)

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(donutSegments.prefix(5))) { segment in
                                    legendRow(segment)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func legendRow(_ segment: DonutSegment) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(segment.color)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(segment.category)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(segment.percentText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.faintText)
            }
            Spacer(minLength: 8)
            Text(insightsCurrencyString(segment.amount))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            metricCard(
                title: "Daily Avg",
                value: insightsCurrencyString(dailyAverage),
                subtitle: selectedTripID == nil ? "Current scope" : "Trip scope"
            )
            metricCard(
                title: "Entries",
                value: "\(scopedExpenses.count)",
                subtitle: "Filtered"
            )
            metricCard(
                title: "Queue",
                value: "\(pendingQueueCount)",
                subtitle: pendingQueueCount == 0 ? "All clear" : "Pending"
            )
        }
    }

    private func metricCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.faintText)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
        )
    }

    private var categoryBreakdownCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Category Breakdown")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text("\(scopedCategoryTotals.count) categories")
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

                    Text("Ranked by spend")
                        .font(.caption)
                        .foregroundStyle(AppTheme.faintText)
                }

                if scopedCategoryTotals.isEmpty {
                    Text("No expenses yet for this filter.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(scopedCategoryTotals.enumerated()), id: \.element.0) { index, row in
                        categoryRow(index: index + 1, category: row.0, total: row.1)
                        if index < scopedCategoryTotals.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
    }

    private func categoryRow(index: Int, category: String, total: Decimal) -> some View {
        let ratio = percentage(for: total)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.muted)
                    .frame(width: 18, alignment: .leading)

                CategoryDot(category: category)

                VStack(alignment: .leading, spacing: 1) {
                    Text(category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.ink)
                    Text("\(Int((ratio * 100).rounded()))% of spend")
                        .font(.caption)
                        .foregroundStyle(AppTheme.faintText)
                }
                Spacer()
                Text(insightsCurrencyString(total))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
            }

            GeometryReader { proxy in
                let width = proxy.size.width.isFinite ? proxy.size.width : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(uiColor: .systemGray5))
                    Capsule()
                        .fill(AppTheme.categoryColor(category))
                        .frame(width: max(8, width * ratio))
                }
            }
            .frame(height: 8)
        }
        .padding(.vertical, 2)
    }

    private var selectedTripName: String {
        if let selectedTripID, let trip = store.trips.first(where: { $0.id == selectedTripID }) {
            return trip.name
        }
        return "All Trips"
    }

    private var selectedPaymentName: String {
        if let selectedPaymentMethodID, let method = store.paymentMethods.first(where: { $0.id == selectedPaymentMethodID }) {
            return method.name
        }
        return "All Payment Methods"
    }

    private var pendingQueueCount: Int {
        store.queuedCaptures.filter { $0.status == .pending || $0.status == .syncing }.count
    }

    private var topCategoryName: String {
        scopedCategoryTotals.first?.0 ?? "None"
    }

    private var dailyAverage: Decimal {
        let divisor = max(1, selectedTripID == nil ? Calendar.current.component(.day, from: .now) : scopedExpenses.count)
        let total = NSDecimalNumber(decimal: scopedTotal).doubleValue
        return Decimal(total / Double(divisor))
    }

    private func percentage(for total: Decimal) -> CGFloat {
        let scopeTotal = NSDecimalNumber(decimal: scopedTotal).doubleValue
        guard scopeTotal > 0 else { return 0 }
        let value = NSDecimalNumber(decimal: total).doubleValue
        let ratio = value / scopeTotal
        if !ratio.isFinite { return 0 }
        return CGFloat(min(max(ratio, 0), 1))
    }

    private func insightsCurrencyString(_ amount: Decimal) -> String {
        let roundedDouble = NSDecimalNumber(decimal: amount).doubleValue.rounded()
        return CurrencyFormatter.string(
            Decimal(roundedDouble),
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        )
    }
}

private struct DonutSegment: Identifiable {
    let id = UUID()
    let category: String
    let amount: Decimal
    let ratio: Double
    let color: Color

    var percentText: String {
        "\(Int((ratio * 100).rounded()))%"
    }
}

private struct DonutChartView: View {
    let segments: [DonutSegment]
    let centerTitle: String
    let centerSubtitle: String

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringThickness = max(18, size * 0.16)
            let inset = ringThickness / 2

            ZStack {
                Circle()
                    .stroke(Color(uiColor: .systemGray5), lineWidth: ringThickness)

                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    let start = startAngle(for: index)
                    let end = start + .degrees(max(2, 360 * segment.ratio))
                    DonutArc(startAngle: start, endAngle: end)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: ringThickness, lineCap: .round))
                        .padding(inset)
                }

                VStack(spacing: 4) {
                    Text(centerTitle)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .multilineTextAlignment(.center)
                    Text(centerSubtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
                .padding(.horizontal, 20)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func startAngle(for index: Int) -> Angle {
        let previousRatio = segments.prefix(index).reduce(0.0) { $0 + $1.ratio }
        return .degrees(-90 + (360 * previousRatio))
    }
}

private struct DonutArc: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}

struct InsightsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            InsightsView()
                .environmentObject(AppStore())
        }
    }
}
