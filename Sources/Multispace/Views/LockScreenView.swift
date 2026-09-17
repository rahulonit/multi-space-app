import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

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

                    Text("Touch ID or your Mac password is required to access your social accounts.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1), in: Capsule())
                }

                Button {
                    triggerUnlock()
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
            .padding(40)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Palette.card, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 30, y: 15)
        }
        .onAppear {
            triggerUnlock()
        }
    }

    private func triggerUnlock() {
        guard !isAuthenticating else { return }
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
