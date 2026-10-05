import SwiftUI

struct UpgradeProSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var licenseService = LicenseService.shared
    var featureReason: String = "Unlock all powerful workspace features"

    @State private var licenseInput = ""
    @State private var isActivating = false
    @State private var activationMessage: String?
    @State private var isSuccess = false

    var body: some View {
        VStack(spacing: 20) {
            headerSection
            featuresSection
            pricingSection
            licenseSection
            dismissButton
        }
        .padding(24)
        .frame(width: 480)
        .background(Palette.window)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.2))
                    .frame(width: 56, height: 56)
                Image(systemName: "crown.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.orange)
            }

            Text("Upgrade to PINGGO Pro")
                .font(.system(size: 20, weight: .bold))

            Text(featureReason)
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow(icon: "person.3.fill", title: "Unlimited Social Accounts", desc: "Connect as many WhatsApp, Slack, Telegram, and Discord profiles as you need (Free: 3 max).")
            featureRow(icon: "rectangle.split.2x1.fill", title: "Split-View & Cross-Pane AI Bridge", desc: "Work in two chats simultaneously and synthesize conversation differences side-by-side.")
            featureRow(icon: "tablecells.badge.ellipsis", title: "Group Member Roster CSV Export", desc: "Extract phone numbers, usernames, and admin roles into formatted CSV/JSON spreadsheets.")
            featureRow(icon: "shield.lefthalf.filled", title: "Ad & Tracker Blocker", desc: "Enjoy faster, ad-free web sessions across all messaging portals.")
        }
        .padding(16)
        .background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var pricingSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("$79 / year")
                    .font(.system(size: 16, weight: .bold))
                Text("or $9.99 billed monthly")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Button {
                if let url = URL(string: "https://pinggo.app/pricing") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Get PINGGO Pro")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Palette.accent, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Already have a license key?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)

            HStack {
                TextField("e.g. PINGGO-XXXX-XXXX-XXXX", text: $licenseInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Button {
                    activateKey()
                } label: {
                    if isActivating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 8)
                    } else {
                        Text("Activate")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licenseInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isActivating)
            }

            if let message = activationMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(isSuccess ? .green : .red)
            }
        }
    }

    private var dismissButton: some View {
        Button("Maybe Later") {
            dismiss()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Palette.muted)
        .padding(.top, 4)
    }

    private func activateKey() {
        isActivating = true
        activationMessage = nil
        Task {
            let result = await licenseService.activate(key: licenseInput)
            isActivating = false
            switch result {
            case .success(let info):
                isSuccess = true
                activationMessage = "Successfully activated \(info.tier.rawValue)!"
                try? await Task.sleep(for: .seconds(1))
                dismiss()
            case .failure(let err):
                isSuccess = false
                activationMessage = err.localizedDescription
            }
        }
    }

    private func featureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Palette.accent)
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
