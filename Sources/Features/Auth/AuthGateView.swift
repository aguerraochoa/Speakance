import SwiftUI

struct AuthGateView: View {
    @EnvironmentObject private var authStore: AuthStore
    @State private var mode: AuthMode = .signIn
    @State private var showPassword = false
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private let authBlue = Color(red: 0.27, green: 0.35, blue: 0.99)
    private let authBlueDim = Color(red: 0.22, green: 0.28, blue: 0.84)
    private let authPanel = Color.black.opacity(0.025)
    private let authField = Color.white

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    authBackground

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            Spacer(minLength: 4)
                            logoLockup
                            titleBlock
                            authFormCard
                            alternateModeButton
                            legalText
                            statusBlock
                            Spacer(minLength: 18)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, max(proxy.safeAreaInsets.top, 8))
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 20, 28))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height, alignment: .top)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .preferredColorScheme(.light)
        }
    }

    private var authBackground: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            LinearGradient(
                colors: [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
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
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("Speakance")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
            Text(mode == .signIn ? "Welcome back" : "Create your account")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(Color.black.opacity(0.45))
        }
        .multilineTextAlignment(.center)
    }

    private var authFormCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 12) {
                fieldContainer {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                }
                .onTapGesture {
                    focusedField = .email
                }

                fieldContainer {
                    HStack(spacing: 10) {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
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
                                .foregroundStyle(Color.black.opacity(0.55))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onTapGesture {
                    focusedField = .password
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(authPanel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    if mode == .signIn {
                        Button("Forgot password?") {
                            focusedField = nil
                            Task { await authStore.sendPasswordReset(email: email) }
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .buttonStyle(.plain)
                        .disabled(authStore.isWorking)
                    } else {
                        Text("Password must be 6+ chars")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.45))
                    }
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
            .foregroundStyle(.black)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Capsule(style: .continuous)
                    .fill(authField)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
    }

    private var alternateModeButton: some View {
        Button {
            mode = mode == .signIn ? .signUp : .signIn
        } label: {
            Text(mode == .signIn ? "Sign up with email" : "Log in")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.black.opacity(0.22), lineWidth: 1.3)
                )
        }
        .buttonStyle(.plain)
    }

    private var legalText: some View {
        Text("By creating an account or using this app, you agree to Speakance's Terms of Use and Privacy Policy")
            .font(.system(size: 12.5, weight: .medium, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.42))
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
            statusCard(
                icon: "bolt.horizontal.fill",
                title: "Authenticating…",
                message: "Validating your session and preparing sync.",
                accent: AppTheme.accent,
                background: [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]
            )
        case let .pendingEmailVerification(email):
            statusCard(
                icon: "envelope.badge",
                title: "Check your email",
                message: "Supabase may require email confirmation before sign in. Check \(email).",
                accent: AppTheme.sky,
                background: [Color(red: 0.94, green: 0.98, blue: 1.0), Color.white]
            )
        case let .passwordResetEmailSent(email):
            statusCard(
                icon: "checkmark.circle.fill",
                title: "Reset email sent",
                message: "If an account exists for \(email), a password reset link has been sent.",
                accent: AppTheme.success,
                background: [Color(red: 0.95, green: 1.0, blue: 0.96), Color.white]
            )
        case let .error(message):
            if isCredentialErrorMessage(message) {
                statusCard(
                    icon: "key.fill",
                    title: "Incorrect email or password",
                    message: "Double-check your credentials or use “Forgot password?”",
                    accent: AppTheme.warning,
                    background: [Color(red: 1.0, green: 0.985, blue: 0.94), Color.white]
                )
            } else {
                statusCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "Couldn’t sign you in",
                    message: message,
                    accent: AppTheme.error,
                    background: [Color(red: 1.0, green: 0.965, blue: 0.965), Color.white]
                )
            }
        case .signedIn:
            EmptyView()
        }
    }

    private func statusCard(
        icon: String,
        title: String,
        message: String,
        accent: Color,
        background: [Color]
    ) -> some View {
        SpeakCard(
            padding: 14,
            cornerRadius: 20,
            fill: AnyShapeStyle(
                LinearGradient(
                    colors: background,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            ),
            stroke: accent.opacity(0.24)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.16))
                            .frame(width: 28, height: 28)
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                }

                Text(message)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func isCredentialErrorMessage(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("incorrect email or password")
            || normalized.contains("invalid login credentials")
            || normalized.contains("invalid credentials")
    }

    private func submit() {
        focusedField = nil
        Task {
            if mode == .signIn {
                await authStore.signIn(email: email, password: password)
            } else {
                await authStore.signUp(email: email, password: password)
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
