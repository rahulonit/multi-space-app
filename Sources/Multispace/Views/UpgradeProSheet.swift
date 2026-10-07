import SwiftUI

struct UpgradeProSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var licenseService = LicenseService.shared
    @ObservedObject private var cloudSync = CloudSyncService.shared
    var featureReason: String = "Unlock all powerful workspace features"

    @State private var licenseInput = ""
    @State private var isActivating = false
    @State private var activationMessage: String?
    @State private var isSuccess = false
    @State private var isProcessingPayment = false
    @State private var selectedBillingCycle: String = "monthly" // "monthly" | "annual"

    var body: some View {
        VStack(spacing: 18) {
            headerSection
            
            if store.isCloudProExpired {
                expiredPlanWarningBanner
            } else if store.isPro {
                activePlanStatusCard
            }
            
            featuresSection
            pricingAndRepaymentSection
            licenseSection
            dismissButton
        }
        .padding(24)
        .frame(width: 500)
        .background(Palette.window)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            ZStack {
                if store.isCloudProExpired {
                    Circle()
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.orange)
                } else if store.isPro {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.green)
                } else {
                    Circle()
                        .fill(Color.yellow.opacity(0.2))
                        .frame(width: 56, height: 56)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Color.orange)
                }
            }

            if store.isCloudProExpired {
                Text("PINGGO Pro Plan Expired")
                    .font(.system(size: 20, weight: .bold))
                Text("Your subscription expired and your account has reverted to the Free tier.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            } else if store.isPro {
                Text("PINGGO Pro Active")
                    .font(.system(size: 20, weight: .bold))
                Text("\(store.preferences.cloudPlanName) • \(store.subscriptionDaysRemaining) days remaining")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            } else {
                Text("Upgrade to PINGGO Pro")
                    .font(.system(size: 20, weight: .bold))
                Text(featureReason)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    private var expiredPlanWarningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18))
                .foregroundStyle(Color.orange)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text("Repayment Required to Restore Pro")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.primary)

                if let expDate = store.preferences.cloudTierExpiresAt {
                    Text("Your plan ended on \(expDate.formatted(date: .abbreviated, time: .shortened)). Free tier allows a maximum of 3 workspaces. Renew now to unlock all your spaces and smart features immediately.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Your Pro subscription has lapsed. Please renew your plan to restore unlimited workspaces.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var activePlanStatusCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Status:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                    Text("Active Pro Member")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.green)
                }

                if let expDate = store.preferences.cloudTierExpiresAt {
                    Text("Valid until: \(expDate.formatted(date: .long, time: .omitted))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                } else {
                    Text("Lifetime license active on this device.")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer()

            Button {
                repayOrUpgrade(plan: "annual")
            } label: {
                if isProcessingPayment {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Extend +1 Year")
                        .font(.system(size: 11.5, weight: .semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isProcessingPayment)
        }
        .padding(12)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.green.opacity(0.25), lineWidth: 1)
        )
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow(icon: "person.3.fill", title: "Unlimited Social Accounts", desc: "Connect as many WhatsApp, Slack, Telegram, and Discord profiles as you need (Free: 3 max).")
            featureRow(icon: "rectangle.split.2x1.fill", title: "Split-View & Cross-Pane AI Bridge", desc: "Work in two chats simultaneously and synthesize conversation differences side-by-side.")
            featureRow(icon: "tablecells.badge.ellipsis", title: "Group Member Roster CSV Export", desc: "Extract phone numbers, usernames, and admin roles into formatted CSV spreadsheets.")
            featureRow(icon: "shield.lefthalf.filled", title: "Ad & Tracker Blocker", desc: "Enjoy faster, ad-free web sessions across all messaging portals.")
        }
        .padding(14)
        .background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var pricingAndRepaymentSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Monthly Plan Option
                Button {
                    repayOrUpgrade(plan: "monthly")
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Monthly")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text("$9.99")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Palette.accent)
                        }
                        Text(store.isCloudProExpired ? "Renew for 30 Days" : "Billed monthly • Cancel anytime")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessingPayment)

                // Annual Plan Option (Recommended)
                Button {
                    repayOrUpgrade(plan: "annual")
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Annual (Best Value)")
                                .font(.system(size: 12, weight: .bold))
                            Spacer()
                            Text("$79")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.green)
                        }
                        Text(store.isCloudProExpired ? "Renew for 1 Year (Save 34%)" : "$6.58/mo billed yearly")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessingPayment)
            }

            if isProcessingPayment {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Processing plan activation...")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 4)
            }
        }
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Have a license key instead?")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.muted)

            HStack {
                TextField("e.g. PINGGO-XXXX-XXXX-XXXX", text: $licenseInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                Button {
                    activateKey()
                } label: {
                    if isActivating {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.horizontal, 6)
                    } else {
                        Text("Activate")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
        Button(store.isPro ? "Close" : "Maybe Later") {
            dismiss()
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Palette.muted)
        .padding(.top, 2)
    }

    private func repayOrUpgrade(plan: String) {
        isProcessingPayment = true
        Task {
            if cloudSync.isCloudConnected {
                let success = await cloudSync.renewOrUpgrade(plan: plan, store: store)
                isProcessingPayment = false
                if success {
                    try? await Task.sleep(for: .seconds(1))
                    dismiss()
                }
            } else {
                // If not connected to MongoDB account, open website checkout
                isProcessingPayment = false
                if let url = URL(string: "https://pinggo.app/pricing") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
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
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
