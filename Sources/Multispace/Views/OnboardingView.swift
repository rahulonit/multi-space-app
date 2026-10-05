import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 24) {
            // Top Indicator
            HStack(spacing: 6) {
                ForEach(0..<3) { idx in
                    Capsule()
                        .fill(idx == currentStep ? Palette.accent : Palette.muted.opacity(0.3))
                        .frame(width: idx == currentStep ? 24 : 8, height: 4)
                        .animation(.spring(response: 0.3), value: currentStep)
                }
            }
            .padding(.top, 24)

            // Content
            TabView(selection: $currentStep) {
                stepView(
                    symbol: "square.stack.3d.up.fill",
                    gradient: [.blue, .cyan],
                    title: "All Your Social Portals in One Place",
                    desc: "Unify WhatsApp, Telegram, Slack, and Discord into isolated workspaces. Run multiple work and personal accounts simultaneously without cookie overlap."
                ).tag(0)

                stepView(
                    symbol: "sparkles",
                    gradient: [.purple, .indigo],
                    title: "In-Context PINGGO AI & Split View",
                    desc: "Analyze conversation transcripts, draft replies, and use Split View (⌘\\) to inspect and synthesize multiple chats side-by-side with AI Bridge."
                ).tag(1)

                stepView(
                    symbol: "lock.shield.fill",
                    gradient: [.green, .teal],
                    title: "Biometric Touch ID & App Lock",
                    desc: "Shield your workspaces with Touch ID or PIN (⌘L). When locked, background observers and accessibility trees are completely suspended."
                ).tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(height: 250)

            // Buttons
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer()

                if currentStep < 2 {
                    Button("Continue") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .controlSize(.regular)
                } else {
                    Button("Get Started") {
                        store.completeOnboarding()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
                    .controlSize(.regular)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 380)
        .background(Palette.window)
    }

    private func stepView(symbol: String, gradient: [Color], title: String, desc: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: gradient.map { $0.opacity(0.2) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(desc)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.horizontal, 16)
    }
}
