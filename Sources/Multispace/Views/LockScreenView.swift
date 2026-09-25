import SwiftUI

@MainActor
struct LockScreenView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var pinInput: String = ""
    @State private var showPinText: Bool = false
    @State private var failedAttempts: Int = 0
    @FocusState private var isPinFocused: Bool

    private var usesPin: Bool {
        store.hasCustomPin || store.preferences.lockMethod == "customPin"
    }

    private var allowsBiometric: Bool {
        !store.hasCustomPin && store.preferences.lockMethod == "biometric"
    }

    var body: some View {
        ZStack {
            // Fullscreen backdrop
            Palette.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // App Icon & Lock Badge
                ZStack(alignment: .bottomTrailing) {
                    AppLogo(size: 80, cornerRadius: 18)
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)

                    ZStack {
                        Circle()
                            .fill(Palette.background)
                            .frame(width: 32, height: 32)
                        Circle()
                            .fill(Palette.accent)
                            .frame(width: 26, height: 26)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 6, y: 6)
                }

                VStack(spacing: 8) {
                    Text("PINGGO is Locked")
                        .font(.system(size: 24, weight: .bold))

                    Text(subtitleText)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                if let error = errorMessage {
                    VStack(spacing: 4) {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)

                        if failedAttempts > 0 && !store.preferences.customPinHint.isEmpty {
                            Text("Hint: \(store.preferences.customPinHint)")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                if usesPin {
                    // Associated account context for Apple Passwords & AutoFill
                    TextField("Account", text: .constant(store.userProfile.email.isEmpty ? "PINGGO Security Lock" : store.userProfile.email))
                        .textContentType(.username)
                        .frame(width: 0, height: 0)
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    // PIN / Password Input Box
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Group {
                                if showPinText {
                                    TextField("Enter PIN or Password", text: $pinInput)
                                        .textContentType(.password)
                                } else {
                                    SecureField("Enter PIN or Password", text: $pinInput)
                                        .textContentType(.password)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .focused($isPinFocused)
                            .onSubmit {
                                submitPin()
                            }

                            Button {
                                showPinText.toggle()
                            } label: {
                                Image(systemName: showPinText ? "eye.slash" : "eye")
                                    .foregroundStyle(Palette.muted)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                            .help(showPinText ? "Hide Password" : "Show Password")

                            Button {
                                autofillFromKeychain()
                            } label: {
                                Image(systemName: "key.fill")
                                    .foregroundStyle(Palette.accent)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                            .help("AutoFill with Apple Passwords / Keychain")

                            Button {
                                submitPin()
                            } label: {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(pinInput.isEmpty ? Palette.muted : Palette.accent)
                            }
                            .buttonStyle(.plain)
                            .disabled(pinInput.isEmpty)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Palette.sidebar, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Palette.card, lineWidth: 1)
                        )
                        .frame(width: 280)

                        // 1-Click Apple Passwords Fill Action
                        Button {
                            autofillFromKeychain()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 11))
                                Text("Fill from Apple Passwords")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                } else {
                    // Biometric Unlock Only (When no custom password is set)
                    Button {
                        triggerBiometricUnlock()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "touchid")
                                .font(.system(size: 18))
                            Text("Unlock PINGGO")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(minWidth: 200, minHeight: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .disabled(isAuthenticating)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(40)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Palette.card, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 30, y: 15)
        }
        .onAppear {
            if usesPin {
                isPinFocused = true
            } else if allowsBiometric {
                triggerBiometricUnlock()
            }
        }
    }

    private var subtitleText: String {
        if usesPin {
            return "Enter your PINGGO PIN or password to unlock."
        } else {
            return "Touch ID or your Mac password is required to access your social accounts."
        }
    }

    private func submitPin() {
        guard !pinInput.isEmpty else { return }
        errorMessage = nil
        let success = store.unlockWithPin(pinInput)
        if success {
            pinInput = ""
            failedAttempts = 0
        } else {
            failedAttempts += 1
            errorMessage = "Incorrect PIN or password. Try again."
            pinInput = ""
            isPinFocused = true
        }
    }

    private func autofillFromKeychain() {
        if let saved = KeychainHelper.getPassword() {
            pinInput = saved
            submitPin()
        } else {
            // Open Apple Passwords app or Settings so user can view/copy saved passwords
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            } else if let url = URL(string: "x-apple.systempreferences:com.apple.Passwords-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            store.showToast("Opening Apple Passwords...")
        }
    }

    private func triggerBiometricUnlock() {
        guard allowsBiometric && !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil
        Task { @MainActor in
            let success = await store.unlockApp()
            isAuthenticating = false
            if !success {
                errorMessage = "Authentication failed. Click to try again."
            }
        }
    }
}
