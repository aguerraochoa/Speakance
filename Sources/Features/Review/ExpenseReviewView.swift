import SwiftUI

struct ExpenseReviewView: View {
    @EnvironmentObject private var store: AppStore
    @State var context: ReviewContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    parsedCard
                    detailsCard
                    aiCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .background(AppCanvasBackground())
            .navigationTitle("Review Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { store.dismissReview() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { store.saveReview(context) }
                        .fontWeight(.bold)
                }
            }
        }
    }

    private var header: some View {
        SpeakCard(padding: 16, cornerRadius: 22, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Confirm parsed expense")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    Text("Edit anything before saving. Fast correction is the trust layer.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                if let confidence = context.draft.parseConfidence {
                    StatusPill(
                        text: "\(Int(confidence * 100))%",
                        color: confidence > 0.9 ? AppTheme.success : AppTheme.warning
                    )
                }
            }
        }
    }

    private var parsedCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Parsed Fields")

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Amount")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.faintText)
                        TextField("Amount", text: $context.draft.amountText)
                            .keyboardType(.decimalPad)
                            .modernField()
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Currency")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.faintText)
                        Menu {
                            ForEach(AppStore.supportedCurrencyCodes, id: \.self) { code in
                                Button(code) { context.draft.currency = code }
                            }
                        } label: {
                            HStack {
                                Text((AppStore.supportedCurrencyCodes.contains(context.draft.currency.uppercased()) ? context.draft.currency.uppercased() : store.defaultCurrencyCode))
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(AppTheme.ink)
                            .modernFieldContainer()
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 110)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(store.categories, id: \.self) { category in
                                Button {
                                    context.draft.category = category
                                } label: {
                                    HStack(spacing: 7) {
                                        CategoryDot(category: category)
                                        Text(category)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(context.draft.category == category ? AppTheme.categoryColor(category).opacity(0.16) : AppTheme.cardStrong)
                                    .overlay(
                                        Capsule().stroke(context.draft.category == category ? AppTheme.categoryColor(category).opacity(0.35) : Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
                                    )
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(AppTheme.ink)
                            }
                        }
                    }
                }

                DatePicker("Date", selection: $context.draft.expenseDate, displayedComponents: .date)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))


                VStack(alignment: .leading, spacing: 8) {
                    Text("Trip")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                    Menu {
                        Button("None") {
                            context.draft.tripID = nil
                            context.draft.tripName = nil
                        }
                        ForEach(store.trips) { trip in
                            Button(trip.name) {
                                context.draft.tripID = trip.id
                                context.draft.tripName = trip.name
                            }
                        }
                    } label: {
                        HStack {
                            Text(context.draft.tripName ?? "No Trip")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(AppTheme.ink)
                        .modernFieldContainer()
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Payment Method")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                    Menu {
                        Button("Unassigned") {
                            context.draft.paymentMethodID = nil
                            context.draft.paymentMethodName = nil
                        }
                        ForEach(store.paymentMethods.filter(\.isActive)) { method in
                            Button(method.name) {
                                context.draft.paymentMethodID = method.id
                                context.draft.paymentMethodName = method.name
                            }
                        }
                    } label: {
                        HStack {
                            Text(context.draft.paymentMethodName ?? "Unassigned")
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                        }
                        .foregroundStyle(AppTheme.ink)
                        .modernFieldContainer()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var detailsCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Details")

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                    TextField("Description", text: $context.draft.description, axis: .vertical)
                        .lineLimit(2...4)
                        .modernField()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Merchant (optional)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.faintText)
                    TextField("Merchant", text: $context.draft.merchant)
                        .modernField()
                }
            }
        }
    }

    private var aiCard: some View {
        SpeakCard(padding: 16, cornerRadius: 22, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.cardStroke) {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Original Capture", subtitle: "Raw text sent to parser")
                Text(context.draft.rawText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppTheme.cardStrong)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

private extension View {
    func modernFieldContainer() -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(AppTheme.cardStrong)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ExpenseReviewView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ExpenseReviewView(context: ReviewContext(draft: ExpenseDraft(source: .text)))
                .environmentObject(AppStore())
        }
    }
}
