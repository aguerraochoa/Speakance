import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedMode: FeedMode = .saved
    @State private var selectedTripFilter: SavedTripFilter = .all
    @State private var selectedCardFilter: SavedCardFilter = .all
    @State private var selectedMonthFilter: SavedMonthFilter = .currentMonth
    @State private var savedLayout: SavedExpenseLayout = .cards
    @State private var selectedPermanentDeleteID: UUID?
    @State private var showingClearAllRecentlyDeletedConfirmation = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header
                        modeSwitcher
                        if selectedMode == .queue {
                            queueHealthCard
                        }

                        if selectedMode == .saved {
                            savedFiltersBar
                            expensesSection
                            if !store.recentlyDeletedExpenses.isEmpty {
                                recentlyDeletedSection
                            }
                        }

                        if selectedMode == .queue {
                            if store.queuedCaptures.isEmpty {
                                SpeakCard(padding: 16, cornerRadius: 20) {
                                    Text("Queue is empty.")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundStyle(AppTheme.muted)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                queueSection
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .background(AppCanvasBackground())

                // Status bar / Dynamic Island scrim so scrolled content doesn't visually collide
                // with the system time/battery indicators.
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(height: proxy.safeAreaInsets.top)
                    Rectangle()
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(height: 10)
                        .overlay(alignment: .bottom) {
                            Divider().opacity(0.08)
                        }
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.isConnected) {
            if store.isConnected {
                await store.syncQueueIfPossible()
            }
        }
    }

    private var header: some View {
        SpeakCard(padding: 16, cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expenses")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppTheme.ink)
                        Text("Full history + offline queue in one timeline")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer()
                    StatusPill(
                        text: store.isSyncingQueue ? "Syncing" : (failedQueueCount > 0 ? "Needs Attention" : "Up to date"),
                        color: store.isSyncingQueue ? AppTheme.warning : (failedQueueCount > 0 ? AppTheme.error : AppTheme.success)
                    )
                }

                HStack(spacing: 10) {
                    MetricChip(
                        title: "Month",
                        value: CurrencyFormatter.string(store.monthlySpendTotal, currency: store.defaultCurrencyCode),
                        tint: AppTheme.accent
                    )
                    MetricChip(title: "Queue", value: "\(store.queuedCaptures.filter { $0.status != .saved }.count)", tint: AppTheme.sky)
                }
            }
        }
    }

    private var queueHealthCard: some View {
        SpeakCard(padding: 14, cornerRadius: 18, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    MetricChip(title: "Pending", value: "\(pendingQueueCount)", tint: AppTheme.butter)
                    MetricChip(title: "Failed", value: "\(failedQueueCount)", tint: AppTheme.coral)
                }

                HStack {
                    Text(lastSyncLabel)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                    Spacer()
                    if failedQueueCount > 0 {
                        Button {
                            store.retryFailedQueueItems()
                        } label: {
                            Label("Retry All", systemImage: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.error)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 8) {
            ForEach(FeedMode.allCases, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    SegmentedPill(title: mode.title, isSelected: selectedMode == mode)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var savedFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Menu {
                    Button("All Trips") { selectedTripFilter = .all }
                    Button("No Trip") { selectedTripFilter = .noTrip }
                    ForEach(store.activeTripFilterOptions) { trip in
                        Button(trip.name) { selectedTripFilter = .trip(trip.id) }
                    }
                } label: {
                    filterChip(title: "Trip", value: selectedTripFilterTitle)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("All Cards") { selectedCardFilter = .all }
                    Button("Unassigned") { selectedCardFilter = .unassigned }
                    ForEach(store.activePaymentMethodOptions) { method in
                        Button(method.name) { selectedCardFilter = .method(method.id) }
                    }
                } label: {
                    filterChip(title: "Card", value: selectedCardFilterTitle)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("All Months") { selectedMonthFilter = .all }
                    ForEach(availableMonthFilters, id: \.self) { month in
                        Button(month.title) { selectedMonthFilter = month }
                    }
                } label: {
                    filterChip(title: "Month", value: selectedMonthFilter.title)
                }
                .buttonStyle(.plain)

                Button {
                    savedLayout = savedLayout == .cards ? .compact : .cards
                } label: {
                    Image(systemName: savedLayout == .cards ? "rectangle.grid.1x2" : "list.bullet")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 22, height: 18)
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.cardStrong, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(savedLayout == .cards ? "Switch to compact list view" : "Switch to card view")
            }
        }
    }

    private func filterChip(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.faintText)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
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
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        )
    }

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Queue",
                subtitle: "Offline captures, sync status, review-needed items",
                trailing: "\(store.queuedCaptures.count) items"
            )

            ForEach(store.queuedCaptures) { item in
                let allowsDelete = store.canDeleteQueueItem(item)
                SwipeRevealExpenseRow(
                    onTap: {
                        if item.status == .needsReview { store.openReview(for: item) }
                    },
                    onDelete: {
                        store.deleteQueueItem(item)
                    },
                    allowsDelete: allowsDelete,
                    cornerRadius: 20,
                    deletePromptTitle: "Delete queue item?",
                    deletePromptMessage: "This removes it from your local queue."
                ) {
                    queueRow(item)
                }
            }
        }
    }

    private var expensesSection: some View {
        let filteredExpenses = filteredSavedExpenses

        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "Saved Expenses",
                subtitle: savedLayout == .cards ? "Tap any expense to edit" : "Compact list view",
                trailing: "\(filteredExpenses.count)"
            )

            if filteredExpenses.isEmpty {
                SpeakCard(padding: 16, cornerRadius: 20) {
                    Text("No saved expenses match the current card/month filters.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(filteredExpenses) { expense in
                    let rowCornerRadius: CGFloat = savedLayout == .cards ? 20 : 14
                    SwipeRevealExpenseRow(
                        onTap: { store.openReview(for: expense) },
                        onDelete: {
                            store.deleteExpense(expense)
                        },
                        allowsDelete: true,
                        cornerRadius: rowCornerRadius,
                        deletePromptTitle: "Move expense to Recently Deleted?",
                        deletePromptMessage: "You can restore it for 30 days."
                    ) {
                        if savedLayout == .cards {
                            expenseRow(expense)
                        } else {
                            compactExpenseRow(expense)
                        }
                    }
                }
            }
        }
    }

    private var recentlyDeletedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                SectionHeader(
                    title: "Recently Deleted",
                    subtitle: "Items are kept for 30 days",
                    trailing: "\(store.recentlyDeletedExpenses.count)"
                )
                Menu {
                    Button(role: .destructive) {
                        showingClearAllRecentlyDeletedConfirmation = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.faintText)
                        .padding(.leading, 6)
                }
                .buttonStyle(.plain)
            }

            ForEach(store.recentlyDeletedExpenses) { entry in
                SpeakCard(padding: 14, cornerRadius: 18, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.expense.category)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.ink)
                                Text(entry.expense.description ?? entry.expense.rawText ?? "Deleted expense")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.muted)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 8)
                            Text(CurrencyFormatter.string(entry.expense.amount, currency: entry.expense.currency))
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.ink)
                        }

                        HStack {
                            Text("Deleted \(entry.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(AppTheme.faintText)
                            Spacer()
                            Text("Long press for actions")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.faintText)
                        }
                    }
                }
                .contentShape(Rectangle())
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    Button {
                        store.restoreRecentlyDeletedExpense(entry.id)
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }

                    Button(role: .destructive) {
                        selectedPermanentDeleteID = entry.id
                    } label: {
                        Label("Delete Permanently", systemImage: "trash")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete permanently?",
            isPresented: Binding(
                get: { selectedPermanentDeleteID != nil },
                set: { if !$0 { selectedPermanentDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = selectedPermanentDeleteID {
                    store.permanentlyDeleteRecentlyDeletedExpense(id)
                }
                selectedPermanentDeleteID = nil
            }
            Button("Cancel", role: .cancel) {
                selectedPermanentDeleteID = nil
            }
        } message: {
            Text("This cannot be undone.")
        }
        .confirmationDialog(
            "Clear all recently deleted?",
            isPresented: $showingClearAllRecentlyDeletedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                store.clearAllRecentlyDeletedExpenses()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes all items in Recently Deleted.")
        }
    }

    @ViewBuilder
    private func queueRow(_ item: QueuedCapture) -> some View {
        SpeakCard(padding: 14, cornerRadius: 20, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(queueColor(item.status).opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: queueIcon(item.status))
                        .foregroundStyle(queueColor(item.status))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(queueDisplayText(for: item))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
                        if let duration = item.audioDurationSeconds {
                            Text("• \(duration)s")
                        }
                        if item.retryCount > 0 {
                            Text("• Retry \(item.retryCount)")
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.faintText)
                    if let error = item.lastError, item.status == .failed {
                        Text(error)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.error)
                            .lineLimit(2)
                    }
                    if item.status == .needsReview {
                        Text("Needs review: tap this item to confirm parsed fields.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.warning)
                    }
                }

                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    QueueBadge(status: item.status)
                    if item.status == .failed || item.status == .pending {
                        Button {
                            store.retryQueueItem(item.id)
                        } label: {
                            Text("Retry")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(AppTheme.accent.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func queueDisplayText(for item: QueuedCapture) -> String {
        let parsedRawText = item.parsedDraft?.rawText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !parsedRawText.isEmpty {
            return parsedRawText
        }
        let localRawText = item.rawText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !localRawText.isEmpty {
            return localRawText
        }
        return "Voice capture"
    }

    @ViewBuilder
    private func expenseRow(_ expense: ExpenseRecord) -> some View {
        SpeakCard(padding: 14, cornerRadius: 20, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.categoryColor(expense.category).opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon(for: expense.category))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.categoryColor(expense.category))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        CategoryDot(category: expense.category)
                        Text(expense.category)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.ink)

                    Text(expense.description ?? "No description")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(expense.expenseDate.formatted(date: .abbreviated, time: .omitted))
                        Text("•")
                        Text(expense.source.rawValue.capitalized)
                        if let trip = expense.tripName {
                            Text("•")
                            Text(trip)
                                .lineLimit(1)
                        }
                        if let method = expense.paymentMethodName {
                            Text("•")
                            Text(method)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.faintText)
                }

                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(CurrencyFormatter.string(expense.amount, currency: expense.currency))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    if let confidence = expense.parseConfidence {
                        Text("\(displayConfidencePercent(for: expense, rawConfidence: confidence))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.faintText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func compactExpenseRow(_ expense: ExpenseRecord) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(AppTheme.categoryColor(expense.category))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(expense.category)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text("•")
                        .foregroundStyle(AppTheme.faintText)
                    Text(expense.expenseDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                        .lineLimit(1)
                }

                Text(expense.description ?? "No description")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)

                if let method = expense.paymentMethodName {
                    Text(method)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(CurrencyFormatter.string(expense.amount, currency: expense.currency))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.cardStrong, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.12), lineWidth: 1)
        )
    }

    private func icon(for category: String) -> String {
        switch category {
        case "Food": return "fork.knife"
        case "Transport": return "car.fill"
        case "Entertainment": return "sparkles.tv"
        case "Shopping": return "bag.fill"
        case "Bills": return "bolt.fill"
        default: return "circle.grid.2x2.fill"
        }
    }

    private func queueIcon(_ status: QueueStatus) -> String {
        switch status {
        case .pending: return "clock.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .needsReview: return "sparkles"
        case .saved: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func queueColor(_ status: QueueStatus) -> Color {
        switch status {
        case .pending, .syncing: return AppTheme.warning
        case .needsReview: return AppTheme.sky
        case .saved: return AppTheme.success
        case .failed: return AppTheme.error
        }
    }

    private func displayConfidencePercent(for expense: ExpenseRecord, rawConfidence: Double) -> Int {
        var confidence = rawConfidence
        let narrative = [expense.rawText ?? "", expense.description ?? ""]
            .joined(separator: " ")
            .lowercased()

        let category = expense.category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !category.isEmpty {
            // Reward explicit category mention in the spoken/text input.
            let normalizedNarrativeWords = Set(
                narrative.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            )
            let categoryWords = category.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            if !categoryWords.isEmpty && categoryWords.allSatisfy({ normalizedNarrativeWords.contains($0) }) {
                confidence += 0.04
            }
        }

        if expense.amount > 0 {
            confidence += 0.015
        }

        let wordCount = (expense.description ?? "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .count
        if wordCount >= 3 {
            confidence += 0.015
        }

        if category == "other" {
            confidence -= 0.04
        }

        let clamped = min(0.99, max(0.40, confidence))
        return Int((clamped * 100).rounded())
    }

    private var filteredSavedExpenses: [ExpenseRecord] {
        store.expenses.filter { expense in
            matchesTripFilter(expense) && matchesCardFilter(expense) && matchesMonthFilter(expense)
        }
    }

    private func matchesTripFilter(_ expense: ExpenseRecord) -> Bool {
        switch selectedTripFilter {
        case .all:
            return true
        case .noTrip:
            return expense.tripID == nil
        case let .trip(id):
            return expense.tripID == id
        }
    }

    private func matchesCardFilter(_ expense: ExpenseRecord) -> Bool {
        switch selectedCardFilter {
        case .all:
            return true
        case .unassigned:
            return expense.paymentMethodID == nil
        case let .method(id):
            return expense.paymentMethodID == id
        }
    }

    private func matchesMonthFilter(_ expense: ExpenseRecord) -> Bool {
        switch selectedMonthFilter {
        case .all:
            return true
        case let .month(year, month):
            let comps = Calendar.current.dateComponents([.year, .month], from: expense.expenseDate)
            return comps.year == year && comps.month == month
        }
    }

    private var availableMonthFilters: [SavedMonthFilter] {
        let calendar = Calendar.current
        let unique = Set(store.expenses.compactMap { expense -> SavedMonthFilter? in
            let comps = calendar.dateComponents([.year, .month], from: expense.expenseDate)
            guard let year = comps.year, let month = comps.month else { return nil }
            return .month(year: year, month: month)
        })
        return unique.sorted(by: { $0.sortKey > $1.sortKey })
    }

    private var selectedCardFilterTitle: String {
        switch selectedCardFilter {
        case .all:
            return "All Cards"
        case .unassigned:
            return "Unassigned"
        case let .method(id):
            return store.paymentMethods.first(where: { $0.id == id })?.name ?? "Unknown"
        }
    }

    private var selectedTripFilterTitle: String {
        switch selectedTripFilter {
        case .all:
            return "All Trips"
        case .noTrip:
            return "No Trip"
        case let .trip(id):
            return store.trips.first(where: { $0.id == id })?.name ?? "Unknown"
        }
    }

    private var failedQueueCount: Int {
        store.queuedCaptures.filter { $0.status == .failed }.count
    }

    private var pendingQueueCount: Int {
        store.queuedCaptures.filter { $0.status == .pending || $0.status == .syncing || $0.status == .needsReview }.count
    }

    private var lastSyncLabel: String {
        if let success = store.lastQueueSyncSuccessAt {
            return "Last successful sync: \(success.formatted(date: .abbreviated, time: .shortened))"
        }
        if let attempted = store.lastQueueSyncAttemptAt {
            return "Last sync attempt: \(attempted.formatted(date: .abbreviated, time: .shortened))"
        }
        return "No sync attempts yet."
    }

}

private enum FeedMode: CaseIterable {
    case saved
    case queue

    var title: String {
        switch self {
        case .saved: return "Saved"
        case .queue: return "Queue"
        }
    }
}

private enum SavedCardFilter: Hashable {
    case all
    case unassigned
    case method(UUID)
}

private enum SavedTripFilter: Hashable {
    case all
    case noTrip
    case trip(UUID)
}

private enum SavedMonthFilter: Hashable {
    case all
    case month(year: Int, month: Int)

    static var currentMonth: SavedMonthFilter {
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

private enum SavedExpenseLayout {
    case cards
    case compact
}

private struct QueueBadge: View {
    let status: QueueStatus

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 1))
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .pending: return "Pending"
        case .syncing: return "Syncing"
        case .needsReview: return "Review"
        case .saved: return "Saved"
        case .failed: return "Failed"
        }
    }

    private var color: Color {
        switch status {
        case .pending, .syncing: return AppTheme.warning
        case .needsReview: return AppTheme.sky
        case .saved: return AppTheme.success
        case .failed: return AppTheme.error
        }
    }
}

struct FeedView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FeedView()
                .environmentObject(AppStore())
        }
    }
}

private struct SwipeRevealExpenseRow<Content: View>: View {
    let onTap: () -> Void
    let onDelete: () -> Void
    let allowsDelete: Bool
    let cornerRadius: CGFloat
    let deletePromptTitle: String
    let deletePromptMessage: String
    @ViewBuilder let content: () -> Content

    @State private var showingDeleteConfirmation = false

    var body: some View {
        content()
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onTapGesture {
                onTap()
            }
            .contextMenu {
                if allowsDelete {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .confirmationDialog(
                deletePromptTitle,
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(deletePromptMessage)
            }
    }
}
