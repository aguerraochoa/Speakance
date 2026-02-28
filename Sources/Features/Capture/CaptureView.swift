import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var store: AppStore
    @State private var quickText = ""
    @State private var mode: CaptureInputMode = .speak
    @State private var isVoiceSessionPrimed = false
    @State private var didRequestVoiceStop = false
    @State private var showingTripSheet = false
    @FocusState private var isQuickTextFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = CaptureLayout(screenSize: proxy.size)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    topBar
                    modePicker
                    tripChipRow

                    if mode == .speak {
                        speakCaptureHero(layout: layout)
                    } else {
                        textCaptureCard(layout: layout)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, max(12, proxy.safeAreaInsets.top > 0 ? 6 : 14))
                .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 8))
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height - 8, alignment: .top)
            }
            .background(AppCanvasBackground())
        }
        .task(id: store.isConnected) {
            if store.isConnected {
                await store.syncQueueIfPossible()
            }
        }
        .onChange(of: mode) { _, _ in
            isVoiceSessionPrimed = false
            didRequestVoiceStop = false
            if mode != .text {
                isQuickTextFocused = false
            }
        }
        .onChange(of: store.audioCaptureService.state) { _, newState in
            if case .idle = newState {
                isVoiceSessionPrimed = false
                didRequestVoiceStop = false
            }
        }
        .sheet(isPresented: $showingTripSheet) {
            TripPickerSheet()
                .environmentObject(store)
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        isQuickTextFocused = false
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Speakance")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                Text("Add an expense fast")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.muted)
            }

            Spacer()

            StatusPill(
                text: store.isConnected ? "Online" : "Offline",
                color: store.isConnected ? AppTheme.success : AppTheme.warning
            )
        }
        .frame(minHeight: 44)
    }

    private var modePicker: some View {
        Picker("Input Mode", selection: $mode) {
            ForEach(CaptureInputMode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Expense input mode")
    }

    private var tripChipRow: some View {
        HStack(spacing: 8) {
            Button {
                showingTripSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.activeTrip == nil ? "airplane" : "airplane.departure")
                        .font(.system(size: 13, weight: .semibold))
                    Text(store.activeTripChipText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.faintText)
                }
                .foregroundStyle(store.activeTrip == nil ? AppTheme.ink : AppTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.cardStrong, in: Capsule())
                .overlay(
                    Capsule().stroke((store.activeTrip == nil ? Color(uiColor: .separator) : AppTheme.accent).opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let activeTrip = store.activeTrip {
                Text(activeTrip.destination?.isEmpty == false ? (activeTrip.destination ?? "") : "Trip tagging active")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func speakCaptureHero(layout: CaptureLayout) -> some View {
        SpeakCard(
            padding: layout.heroPadding,
            cornerRadius: 28,
            fill: AnyShapeStyle(AppTheme.cardStrong),
            stroke: Color(uiColor: .separator).opacity(0.16)
        ) {
            VStack(spacing: 0) {
                Text(isRecordInteractionActive ? "Tap to stop" : "Tap to record")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                Spacer(minLength: layout.heroTopGap)

                recordControl(layout: layout)

                Spacer(minLength: layout.heroBottomGap)

                Text(recordStatusSubtitle)
                    .font(isRecording ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .padding(.bottom, 10)

                Button {
                    isVoiceSessionPrimed = false
                    didRequestVoiceStop = false
                    store.cancelRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .bold))
                        Text("Discard")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(AppTheme.error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.error.opacity(0.09), in: Capsule())
                    .overlay(
                        Capsule().stroke(AppTheme.error.opacity(0.18), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isRecordInteractionActive)
                .opacity(isRecordInteractionActive ? 1 : 0)
                .allowsHitTesting(isRecordInteractionActive)
                .frame(height: 42)
                .padding(.bottom, 4)

                if let audioError = store.audioCaptureService.lastErrorMessage {
                    Text(audioError)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.error)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: layout.heroMinHeight, alignment: .center)
        }
    }

    @ViewBuilder
    private func recordControl(layout: CaptureLayout) -> some View {
        let loginNavy = Color(red: 0.03, green: 0.11, blue: 0.28)
        let loginNavyDeep = Color(red: 0.01, green: 0.05, blue: 0.16)
        let loginBlueGlow = Color(red: 0.27, green: 0.35, blue: 0.99)

        ZStack {
            Circle()
                .fill((isRecordInteractionActive ? AppTheme.accent : loginBlueGlow).opacity(0.06))
                .frame(width: layout.ringFrame, height: layout.ringFrame)

            AudioPulseRings(isActive: isRecording, color: isRecordInteractionActive ? AppTheme.accent : loginBlueGlow)
                .frame(width: layout.ringFrame - 6, height: layout.ringFrame - 6)

            Circle()
                .fill(
                    LinearGradient(
                        colors: isRecordInteractionActive
                            ? [Color(uiColor: .systemRed), Color(uiColor: .systemPink)]
                            : [loginNavy, loginNavyDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: layout.buttonCircle, height: layout.buttonCircle)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1.2))
                .shadow(color: (isRecordInteractionActive ? AppTheme.accent : loginBlueGlow).opacity(0.18), radius: 20, y: 10)

            Image(systemName: isRecordInteractionActive ? "waveform" : "waveform.circle.fill")
                .font(.system(size: layout.micIconSize, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(Circle())
        .onTapGesture {
            if isRecordInteractionActive {
                isVoiceSessionPrimed = false
                didRequestVoiceStop = true
                store.stopRecordingAndCreateEntry()
            } else {
                isVoiceSessionPrimed = true
                didRequestVoiceStop = false
                store.startRecording()
            }
        }
        .accessibilityElement()
        .accessibilityLabel(isRecordInteractionActive ? "Recording. Tap to stop" : "Tap to start recording")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func textCaptureCard(layout: CaptureLayout) -> some View {
        SpeakCard(
            padding: 18,
            cornerRadius: 24,
            fill: AnyShapeStyle(AppTheme.cardStrong),
            stroke: Color(uiColor: .separator).opacity(0.16)
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Type an expense")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.ink)

                TextField("Describe the expense...", text: $quickText, axis: .vertical)
                    .lineLimit(3...6)
                    .modernField()
                    .focused($isQuickTextFocused)

                Button {
                    isQuickTextFocused = false
                    store.createTextEntry(rawText: quickText)
                    quickText = ""
                } label: {
                    Label("Parse & Save", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [AppTheme.accent, Color(uiColor: .systemBlue)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(quickText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var isRecording: Bool {
        if case .recording = store.audioCaptureService.state { return true }
        return false
    }

    private var isRecordInteractionActive: Bool {
        if isVoiceSessionPrimed { return true }
        switch store.audioCaptureService.state {
        case .requestingPermission, .recording, .processing:
            return true
        case .idle:
            return false
        }
    }

    private var recordStatusSubtitle: String {
        switch store.audioCaptureService.state {
        case .requestingPermission:
            return "Allow microphone access to start recording"
        case .recording:
            if didRequestVoiceStop {
                return "Processing recording..."
            }
            return "Listening... Tap again to send"
        case .processing:
            return "Processing recording..."
        case .idle:
            return "One expense • \(store.maxVoiceCaptureSeconds) seconds max"
        }
    }

    @ViewBuilder
    private func suggestionChip(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.cardStrong, in: Capsule())
            .overlay(
                Capsule().stroke(Color(uiColor: .separator).opacity(0.16), lineWidth: 1)
            )
            .onTapGesture {
                quickText = text
                isQuickTextFocused = false
            }
    }
}

private enum CaptureInputMode: CaseIterable {
    case speak
    case text

    var title: String {
        switch self {
        case .speak: return "Speak"
        case .text: return "Text"
        }
    }
}

private struct TripPickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var newTripName = ""
    @State private var baseCurrency: String? = nil
    @State private var startDate = Date()
    @State private var endDate: Date? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Active Trip") {
                    Button(store.activeTrip == nil ? "No Trip" : "Clear Active Trip") {
                        store.endActiveTrip()
                    }
                    .foregroundStyle(AppTheme.ink)
                }

                if !store.trips.isEmpty {
                    Section("Your Trips") {
                        ForEach(store.trips) { trip in
                            Button {
                                store.selectTrip(trip.id)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(trip.name)
                                        Spacer()
                                        if store.activeTripID == trip.id {
                                            Text("Active")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                    }
                                    if let destination = trip.destination {
                                        Text(destination)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Start New Trip") {
                    TextField("Trip name (e.g. Japan 2026)", text: $newTripName)
                    Menu {
                        Button("Use app default (\(store.defaultCurrencyCode))") { baseCurrency = nil }
                        ForEach(AppStore.supportedCurrencyCodes, id: \.self) { code in
                            Button(code) { baseCurrency = code }
                        }
                    } label: {
                        HStack {
                            Text("Base currency")
                            Spacer()
                            Text(baseCurrency ?? "Use app default (\(store.defaultCurrencyCode))")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    Button("Create and Set Active") {
                        store.addTrip(
                            name: newTripName,
                            startDate: startDate,
                            endDate: endDate,
                            baseCurrency: baseCurrency ?? store.defaultCurrencyCode,
                            setActive: true
                        )
                        dismiss()
                    }
                    .disabled(newTripName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct CaptureLayout {
    let screenSize: CGSize

    var isLargePhone: Bool { screenSize.height >= 860 }
    var isMaxPhone: Bool { screenSize.height >= 920 || screenSize.width >= 428 }

    var horizontalPadding: CGFloat { isMaxPhone ? 18 : 16 }
    var heroPadding: CGFloat { isMaxPhone ? 24 : 18 }

    var ringFrame: CGFloat {
        let proposed = min(screenSize.width * 0.72, isMaxPhone ? 330 : 292)
        return max(236, proposed)
    }

    var buttonCircle: CGFloat {
        min(ringFrame * 0.80, isMaxPhone ? 260 : 236)
    }

    var micIconSize: CGFloat {
        isMaxPhone ? 58 : 52
    }

    var heroMinHeight: CGFloat {
        let proposed = screenSize.height * (isMaxPhone ? 0.62 : 0.56)
        return min(max(proposed, 480), 720)
    }

    var heroTopGap: CGFloat {
        isMaxPhone ? 28 : 22
    }

    var heroBottomGap: CGFloat {
        isMaxPhone ? 30 : 24
    }

    var textCardMinHeight: CGFloat {
        let proposed = screenSize.height * 0.44
        return max(340, min(proposed, 500))
    }
}

struct CaptureView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CaptureView()
                .environmentObject(AppStore())
                .previewDisplayName("iPhone 16 Pro")
            CaptureView()
                .environmentObject(AppStore())
                .previewDevice("iPhone 16 Pro Max")
                .previewDisplayName("iPhone 16 Pro Max")
        }
    }
}
