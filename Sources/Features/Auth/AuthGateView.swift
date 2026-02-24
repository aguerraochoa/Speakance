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
    private let authPanel = Color.black.opacity(0.025)
    private let authField = Color.white

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
                                .foregroundStyle(Color.black.opacity(0.55))
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
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    if mode == .signIn {
                        Button("Forgot password?") {
                            focusedField = nil
                            Task { await authStore.sendPasswordReset() }
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
        case let .passwordResetEmailSent(email):
            SpeakCard(padding: 14, cornerRadius: 18, fill: AnyShapeStyle(AppTheme.cardStrong), stroke: AppTheme.success.opacity(0.22)) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reset email sent")
                        .font(.headline)
                        .foregroundStyle(AppTheme.success)
                    Text("If an account exists for \(email), a password reset link has been sent.")
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
