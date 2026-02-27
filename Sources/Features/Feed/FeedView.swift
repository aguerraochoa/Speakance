import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedMode: FeedMode = .saved
    @State private var selectedTripFilter: SavedTripFilter = .all
    @State private var selectedCardFilter: SavedCardFilter = .all
    @State private var selectedMonthFilter: SavedMonthFilter = .currentMonth
    @State private var savedLayout: SavedExpenseLayout = .cards

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        header
                        modeSwitcher

                        if selectedMode == .saved {
                            savedFiltersBar
                            expensesSection
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
                        text: store.isSyncingQueue ? "Syncing" : "Up to date",
                        color: store.isSyncingQueue ? AppTheme.warning : AppTheme.success
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
                SwipeRevealExpenseRow(
                    onTap: {
                        if item.status == .needsReview { store.openReview(for: item) }
                    },
                    onDelete: {
                        store.deleteQueueItem(item)
                    }
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
                    SwipeRevealExpenseRow(
                        onTap: { store.openReview(for: expense) },
                        onDelete: { store.deleteExpense(expense) }
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
                }

                Spacer(minLength: 8)
                QueueBadge(status: item.status)
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
                        Text("\(Int(confidence * 100))%")
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
    @ViewBuilder let content: () -> Content

    @State private var revealedOffset: CGFloat = 0
    @State private var rowWidth: CGFloat = 0
    @State private var deleting = false
    @State private var deleteTravelOffset: CGFloat = 0
    @GestureState private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 112
    private let rowCornerRadius: CGFloat = 20

    var body: some View {
        ZStack(alignment: .leading) {
            deleteBackground

            content()
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !deleting else { return }
                    if revealedOffset > 0 {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                            revealedOffset = 0
                        }
                    } else {
                        onTap()
                    }
                }
                .offset(x: currentOffset)
                .simultaneousGesture(dragGesture)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { rowWidth = proxy.size.width }
                            .onChange(of: proxy.size.width) { _, newValue in
                                rowWidth = newValue
                            }
                    }
                )
        }
    }

    private var currentOffset: CGFloat {
        if deleting {
            return deleteTravelOffset
        }
        let raw = max(0, revealedOffset + dragTranslation)
        if raw <= actionWidth {
            return raw
        }
        // Rubber-band past the reveal width so it doesn't feel "stuck" while dragging.
        let overshoot = raw - actionWidth
        return actionWidth + (overshoot * 0.22)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                guard !deleting else { return }
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > 8, horizontal > vertical else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard !deleting else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let fullSwipeThreshold = max(actionWidth * 1.6, min(220, rowWidth * 0.52))
                let projected = max(value.translation.width, value.predictedEndTranslation.width)
                if projected >= fullSwipeThreshold {
                    let startOffset = max(currentOffset, actionWidth)
                    revealedOffset = actionWidth
                    deleteTravelOffset = startOffset
                    let target = max((rowWidth > 0 ? rowWidth : 320) + 28, actionWidth + 40)
                    deleting = true
                    withAnimation(.easeOut(duration: 0.16)) {
                        deleteTravelOffset = target
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        onDelete()
                    }
                    return
                }
                let proposed = min(max(0, revealedOffset + value.translation.width), actionWidth)
                withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.92, blendDuration: 0.05)) {
                    revealedOffset = proposed > actionWidth * 0.33 ? actionWidth : 0
                }
            }
    }

    private var deleteBackground: some View {
        let revealProgress = max(0, min(1, currentOffset / actionWidth))
        let fullWidth = max(rowWidth, 1)
        let revealWidth = deleting ? fullWidth : max(0, currentOffset)
        let backgroundWidth = deleting ? fullWidth : revealWidth

        return ZStack(alignment: .leading) {
            if backgroundWidth > 0.5 {
                Color.red
                    .frame(width: min(max(0, backgroundWidth), fullWidth))
                    .clipShape(
                        deleting
                        ? AnyShape(RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous))
                        : AnyShape(LeadingActionShape(cornerRadius: rowCornerRadius))
                    )
                    .overlay(alignment: .leading) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: max(44, min(actionWidth, max(0, backgroundWidth))), alignment: .center)
                            .opacity(deleting ? 1 : max(0.18, revealProgress))
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !deleting else { return }
            guard currentOffset > 0 else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                revealedOffset = 0
            }
        }
        .overlay(alignment: .leading) {
            // Tap-to-delete when revealed but not full-swiped.
            if currentOffset > 8 {
                Color.clear
                    .frame(width: min(actionWidth, max(0, currentOffset)))
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !deleting else { return }
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                            revealedOffset = 0
                        }
                        onDelete()
                    }
            }
        }
    }
}

private struct LeadingActionShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let r = min(cornerRadius, rect.height / 2, rect.width)
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + r, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
