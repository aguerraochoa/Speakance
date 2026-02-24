import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var mode: AuthMode = .signIn
    @State private var showPassword = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private let authBlue = Color(red: 0.27, green: 0.35, blue: 0.99)
    private let authBlueDim = Color(red: 0.22, green: 0.28, blue: 0.84)
    private let authBorder = Color.white.opacity(0.22)
    private let authPanel = Color.white.opacity(0.035)
    private let authField = Color.white.opacity(0.045)
    private let iconNavy = Color(red: 0.03, green: 0.11, blue: 0.28)
    private let iconNavyDeep = Color(red: 0.01, green: 0.05, blue: 0.16)

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    authBackground
                        .onTapGesture {
                            focusedField = nil
                        }

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            Spacer(minLength: max(24, proxy.size.height * 0.06))
                            logoLockup
                            titleBlock
                            authModeToggle
                            authFormCard
                            alternateModeButton
                            appleButton
                            legalText
                            statusBlock
                            Spacer(minLength: 18)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, max(proxy.safeAreaInsets.top + 4, 16))
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 20, 28))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height, alignment: .top)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    private var authBackground: some View {
        ZStack {
            iconNavy.ignoresSafeArea()

            LinearGradient(
                colors: [iconNavy, iconNavyDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.05), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [authBlue.opacity(0.16), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()
            .blur(radius: 14)
        }
    }

    private var logoLockup: some View {
        Image("AuthHeaderLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: authBlue.opacity(0.20), radius: 22, y: 10)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("Speakance")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(mode == .signIn ? "Welcome back" : "Create your account")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.75))
        }
        .multilineTextAlignment(.center)
    }

    private var authModeToggle: some View {
        HStack(spacing: 8) {
            modePill(title: "Sign In", selected: mode == .signIn) {
                mode = .signIn
            }
            modePill(title: "Create Account", selected: mode == .signUp) {
                mode = .signUp
            }
        }
    }

    private func modePill(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? .white : Color.white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? authBlue.opacity(0.92) : Color.clear)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(selected ? authBlue : authBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var authFormCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                fieldContainer {
                    TextField("Email", text: $authStore.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }

                fieldContainer {
                    HStack(spacing: 10) {
                        Group {
                            if showPassword {
                                TextField("Password", text: $authStore.password)
                            } else {
                                SecureField("Password", text: $authStore.password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(authPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    Button(mode == .signIn ? "Recovery Password" : "Password must be 6+ chars") {
                        // Placeholder action for now
                    }
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .buttonStyle(.plain)
                    .disabled(mode != .signIn)
                    .opacity(mode == .signIn ? 1 : 0.75)
                }

                Button(action: submit) {
                    HStack(spacing: 10) {
                        if authStore.isWorking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(mode == .signIn ? "Log in" : "Sign up with email")
                            .font(.system(size: 19, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [authBlue, authBlueDim],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(authStore.isWorking)
                .opacity(authStore.isWorking ? 0.75 : 1)
            }
        }
    }

    @ViewBuilder
    private func fieldContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule(style: .continuous)
                    .fill(authField)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }

    private var alternateModeButton: some View {
        Button {
            mode = mode == .signIn ? .signUp : .signIn
        } label: {
            Text(mode == .signIn ? "Sign up with email" : "Log in")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1.3)
                )
        }
        .buttonStyle(.plain)
    }

    private var appleButton: some View {
        Button {
            // Placeholder UI only for now
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .semibold))
                Text("Continue with Apple")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1.3)
            )
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.9)
    }

    private var legalText: some View {
        Text("By creating an account or using this app, you agree to Speakance's Terms of Use and Privacy Policy")
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.65))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var statusBlock: some View {
        switch authStore.state {
        case .disabled:
            EmptyView()
        case .signedOut:
            EmptyView()
        case .loading:
            SpeakCard(padding: 14, cornerRadius: 18) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Authenticating…")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .pendingEmailVerification(email):
            SpeakCard(padding: 14, cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check your email")
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text("Supabase may require email confirmation before sign in. Check \(email).")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .error(message):
            SpeakCard(padding: 14, cornerRadius: 18, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.error.opacity(0.25)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Auth Error")
                        .font(.headline)
                        .foregroundStyle(AppTheme.error)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.muted)
                    Button("Dismiss") {
                        authStore.dismissErrorIfNeeded()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .signedIn:
            EmptyView()
        }
    }

    private func submit() {
        focusedField = nil
        Task {
            if mode == .signIn {
                await authStore.signIn()
            } else {
                await authStore.signUp()
            }
        }
    }
}

private enum AuthMode {
    case signIn
    case signUp
}

struct AuthGateView_Previews: PreviewProvider {
    static var previews: some View {
        AuthGateView()
            .environmentObject(AuthStore(client: nil, tokenStore: SharedAccessTokenStore()))
    }
}
