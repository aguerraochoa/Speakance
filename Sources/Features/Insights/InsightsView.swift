import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedTripID: UUID?
    @State private var selectedPaymentMethodID: UUID?
    @State private var selectedCurrencyCode = "USD"
    @State private var selectedMonthFilter: InsightsMonthFilter = .currentMonth
    @State private var selectedTrendYear: Int = Calendar.current.component(.year, from: .now)
    @State private var selectedTrendSegment: TrendChartSelection?

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    filtersCard
                    summaryRow
                    donutCard
                    yearlyCategoryTrendCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, max(28, proxy.safeAreaInsets.bottom + 8))
            }
            .background(AppCanvasBackground())
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            let options = availableCurrencyCodes
            if options.contains(store.defaultCurrencyCode) {
                selectedCurrencyCode = store.defaultCurrencyCode
            } else if let first = options.first {
                selectedCurrencyCode = first
            }
        }
        .onChange(of: selectedTripID) {
            selectedTrendSegment = nil
            ensureSelectedCurrencyIsAvailable()
        }
        .onChange(of: selectedPaymentMethodID) {
            selectedTrendSegment = nil
            ensureSelectedCurrencyIsAvailable()
        }
        .onChange(of: selectedCurrencyCode) { selectedTrendSegment = nil }
        .onChange(of: selectedTrendYear) { selectedTrendSegment = nil }
    }

    private var baseFilteredExpenses: [ExpenseRecord] {
        store.filteredExpenses(tripID: selectedTripID, paymentMethodID: selectedPaymentMethodID)
    }

    private var availableCurrencyCodes: [String] {
        let detected = Set(baseFilteredExpenses.compactMap { code in
            let trimmed = code.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return trimmed.isEmpty ? nil : trimmed
        })
        let merged = detected.union([store.defaultCurrencyCode])
        return merged.sorted { lhs, rhs in
            if lhs == store.defaultCurrencyCode { return true }
            if rhs == store.defaultCurrencyCode { return false }
            return lhs < rhs
        }
    }

    private var currencyScopedExpenses: [ExpenseRecord] {
        baseFilteredExpenses.filter {
            $0.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == selectedCurrencyCode
        }
    }

    private var scopedExpenses: [ExpenseRecord] {
        currencyScopedExpenses.filter { expense in
            switch selectedMonthFilter {
            case .all:
                return true
            case let .month(year, month):
                let comps = Calendar.current.dateComponents([.year, .month], from: expense.expenseDate)
                return comps.year == year && comps.month == month
            }
        }
    }

    private var scopedCategoryTotals: [(String, Decimal)] {
        let totals = scopedExpenses.reduce(into: [String: Decimal]()) { partial, expense in
            partial[expense.category, default: .zero] += expense.amount
        }
        return totals.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
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
        SpeakCard(padding: 12, cornerRadius: 20) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Menu {
                        Button("All Trips") { selectedTripID = nil }
                        ForEach(store.activeTripFilterOptions) { trip in
                            Button(trip.name) { selectedTripID = trip.id }
                        }
                    } label: {
                        compactFilterChip(title: "Trip", value: selectedTripName)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("All Cards") { selectedPaymentMethodID = nil }
                        ForEach(store.activePaymentMethodOptions) { method in
                            Button(method.name) { selectedPaymentMethodID = method.id }
                        }
                    } label: {
                        compactFilterChip(title: "Card", value: selectedPaymentName == "All Payment Methods" ? "All Cards" : selectedPaymentName)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("All Months") { selectedMonthFilter = .all }
                        ForEach(availableMonthFilters, id: \.self) { month in
                            Button(month.title) { selectedMonthFilter = month }
                        }
                    } label: {
                        compactFilterChip(title: "Month", value: selectedMonthFilter.title)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(availableCurrencyCodes, id: \.self) { currency in
                            Button(currency) { selectedCurrencyCode = currency }
                        }
                    } label: {
                        compactFilterChip(title: "Currency", value: selectedCurrencyCode)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func compactFilterChip(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.faintText)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.faintText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.cardStrong, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
        )
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

    private func ensureSelectedCurrencyIsAvailable() {
        if availableCurrencyCodes.contains(selectedCurrencyCode) { return }
        selectedCurrencyCode = availableCurrencyCodes.first ?? store.defaultCurrencyCode
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
                value: insightsCurrencyString(dailyAverage)
            )
            metricCard(
                title: "Entries",
                value: "\(scopedExpenses.count)"
            )
            metricCard(
                title: "Queue",
                value: "\(pendingQueueCount)"
            )
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.faintText)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
        )
    }

    private var yearlyCategoryTrendCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Monthly Categories")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Menu {
                            ForEach(availableTrendYears, id: \.self) { year in
                                Button(action: { selectedTrendYear = year }) {
                                    Text(verbatim: String(year))
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(verbatim: String(selectedTrendYear))
                                    .font(.caption.weight(.semibold))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(AppTheme.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppTheme.cardStrong, in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Stacked monthly spend by category (\(String(selectedTrendYear)))")
                        .font(.caption)
                        .foregroundStyle(AppTheme.faintText)
                }

                Group {
                    if let selection = selectedTrendSegment {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(AppTheme.categoryColor(selection.category))
                                .frame(width: 8, height: 8)
                            Text(selection.category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            Spacer(minLength: 8)
                            Text(insightsCurrencyString(selection.amount))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.ink)
                            Text(selection.percentText)
                                .font(.caption)
                                .foregroundStyle(AppTheme.faintText)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.clear)
                                .frame(width: 8, height: 8)
                            Text("Tap a category segment to see details.")
                                .font(.caption)
                                .foregroundStyle(AppTheme.faintText)
                            Spacer(minLength: 8)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 38)
                .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.14), lineWidth: 1)
                )

                MonthlyCategoryStackedChartView(months: trendChartMonths, selection: $selectedTrendSegment)
                    .frame(height: 240)

                if trendLegendCategories.isEmpty {
                    Text("No expenses for this year under the current trip/card filters.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(trendLegendCategories, id: \.self) { category in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(AppTheme.categoryColor(category))
                                        .frame(width: 8, height: 8)
                                    Text(category)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(AppTheme.ink)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(AppTheme.cardStrong, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color(uiColor: .separator).opacity(0.14), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
            }
        }
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

    private var availableMonthFilters: [InsightsMonthFilter] {
        let calendar = Calendar.current
        let unique = Set(currencyScopedExpenses.compactMap { expense -> InsightsMonthFilter? in
            let comps = calendar.dateComponents([.year, .month], from: expense.expenseDate)
            guard let year = comps.year, let month = comps.month else { return nil }
            return .month(year: year, month: month)
        })
        return unique.sorted(by: { $0.sortKey > $1.sortKey })
    }

    private var availableTrendYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: .now)
        let years = Set(currencyScopedExpenses.compactMap { Calendar.current.dateComponents([.year], from: $0.expenseDate).year })
            .union([currentYear])
        return years.sorted(by: >)
    }

    private var trendYearExpenses: [ExpenseRecord] {
        currencyScopedExpenses.filter {
            Calendar.current.component(.year, from: $0.expenseDate) == selectedTrendYear
        }
    }

    private var trendLegendCategories: [String] {
        let totals = trendYearExpenses.reduce(into: [String: Decimal]()) { partial, expense in
            partial[expense.category, default: .zero] += expense.amount
        }
        return totals
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .map(\.key)
    }

    private var trendChartMonths: [MonthlyCategoryStack] {
        let calendar = Calendar.current
        let monthCategoryTotals = trendYearExpenses.reduce(into: [Int: [String: Decimal]]()) { partial, expense in
            let month = calendar.component(.month, from: expense.expenseDate)
            var bucket = partial[month] ?? [:]
            bucket[expense.category, default: .zero] += expense.amount
            partial[month] = bucket
        }

        let categoryOrder = trendLegendCategories

        return (1...12).map { month in
            let categoryMap = monthCategoryTotals[month] ?? [:]
            let segments = categoryOrder.compactMap { category -> MonthlyCategoryStackSegment? in
                guard let amount = categoryMap[category], amount > 0 else { return nil }
                return MonthlyCategoryStackSegment(
                    category: category,
                    amount: amount,
                    color: AppTheme.categoryColor(category)
                )
            }
            let total = segments.reduce(Decimal.zero) { $0 + $1.amount }
            return MonthlyCategoryStack(month: month, total: total, segments: segments)
        }
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

    private func insightsCurrencyString(_ amount: Decimal) -> String {
        let roundedDouble = NSDecimalNumber(decimal: amount).doubleValue.rounded()
        return CurrencyFormatter.string(
            Decimal(roundedDouble),
            currency: store.defaultCurrencyCode,
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        )
    }

}

private enum InsightsMonthFilter: Hashable {
    case all
    case month(year: Int, month: Int)

    static var currentMonth: InsightsMonthFilter {
        let comps = Calendar.current.dateComponents([.year, .month], from: .now)
        return .month(year: comps.year ?? 0, month: comps.month ?? 1)
    }

    var title: String {
        switch self {
        case .all:
            return "All Months"
        case let .month(year, month):
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = 1
            let date = Calendar.current.date(from: comps) ?? .now
            return date.formatted(.dateTime.month(.abbreviated).year())
        }
    }

    var sortKey: Int {
        switch self {
        case .all:
            return Int.min
        case let .month(year, month):
            return year * 100 + month
        }
    }
}

private struct MonthlyCategoryStack: Identifiable {
    let month: Int
    let total: Decimal
    let segments: [MonthlyCategoryStackSegment]

    var id: Int { month }
}

private struct MonthlyCategoryStackSegment: Identifiable {
    let id = UUID()
    let category: String
    let amount: Decimal
    let color: Color
}

private struct TrendChartSelection: Equatable {
    let month: Int
    let category: String
    let amount: Decimal
    let monthTotal: Decimal

    var ratio: Double {
        let total = NSDecimalNumber(decimal: monthTotal).doubleValue
        guard total > 0 else { return 0 }
        return max(0, min(1, NSDecimalNumber(decimal: amount).doubleValue / total))
    }

    var percentText: String {
        "\(Int((ratio * 100).rounded()))% of month"
    }
}

private struct MonthlyCategoryStackedChartView: View {
    let months: [MonthlyCategoryStack]
    @Binding var selection: TrendChartSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(months) { month in
                    monthBar(month)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                ForEach(months) { month in
                    Text(monthLabel(month.month))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.faintText)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func monthBar(_ month: MonthlyCategoryStack) -> some View {
        let maxTotal = max(
            1,
            months.map { NSDecimalNumber(decimal: $0.total).doubleValue }.max() ?? 1
        )
        let monthTotal = NSDecimalNumber(decimal: month.total).doubleValue

        GeometryReader { proxy in
            let height = max(1, proxy.size.height)
            let barHeight = CGFloat(monthTotal / maxTotal) * height

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if monthTotal > 0 {
                    VStack(spacing: 0) {
                        ForEach(Array(month.segments.reversed())) { segment in
                            let amount = NSDecimalNumber(decimal: segment.amount).doubleValue
                            let isSelected = selection?.month == month.month && selection?.category == segment.category
                            let isDimmed = selection != nil && !isSelected
                            Rectangle()
                                .fill(segment.color)
                                .frame(height: max(2, barHeight * CGFloat(amount / monthTotal)))
                                .opacity(isDimmed ? 0.28 : 1)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    let next = TrendChartSelection(
                                        month: month.month,
                                        category: segment.category,
                                        amount: segment.amount,
                                        monthTotal: month.total
                                    )
                                    if selection?.month == next.month && selection?.category == next.category {
                                        selection = nil
                                    } else {
                                        selection = next
                                    }
                                }
                        }
                    }
                    .frame(height: barHeight, alignment: .bottom)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.black.opacity(0.03), lineWidth: 0.5)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .onTapGesture {
                if monthTotal == 0 { selection = nil }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
    }

    private func monthLabel(_ month: Int) -> String {
        let symbols = Calendar.current.veryShortMonthSymbols
        guard month >= 1, month <= symbols.count else { return "-" }
        return symbols[month - 1]
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
