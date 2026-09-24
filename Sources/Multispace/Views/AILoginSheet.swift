import SwiftUI

struct AILoginProviderItem: Identifiable {
    let id: String
}

/// A single, honest connection flow for hosted AI providers. Consumer website
/// cookies are intentionally not treated as API credentials.
struct AILoginWebSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let provider: String // "gemini" or "chatgpt"

    @State private var credential = ""
    @State private var isShowingCredential = false
    @State private var isTesting = false
    @State private var result: (success: Bool, message: String)?

    private var isGemini: Bool { provider == "gemini" }
    private var providerName: String { isGemini ? "Google Gemini" : "OpenAI" }
    private var credentialName: String { isGemini ? "Gemini API key" : "OpenAI API key" }
    private var placeholder: String { isGemini ? "Paste Gemini API key" : "sk-proj-…" }
    private var model: String {
        isGemini ? store.preferences.geminiModelTier : store.preferences.openAiModelTier
    }
    private var providerColor: Color {
        isGemini ? Color(red: 0.26, green: 0.52, blue: 0.96) : Color(red: 0.06, green: 0.65, blue: 0.53)
    }
    private var isCurrentlyConnected: Bool {
        isGemini
            ? (!store.preferences.geminiApiKey.isEmpty && store.preferences.isGeminiLoggedIn)
            : (!store.preferences.openAiApiKey.isEmpty && store.preferences.isChatGptLoggedIn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(providerColor.opacity(0.14)).frame(width: 42, height: 42)
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(providerColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect \(providerName)")
                        .font(.system(size: 18, weight: .bold))
                    Text("Validate once, then store the credential in macOS Keychain.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                if isCurrentlyConnected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("How to connect")
                    .font(.system(size: 13, weight: .bold))
                instructionRow(number: 1, text: isGemini
                    ? "Open Google AI Studio and sign in with your Google account."
                    : "Open the OpenAI Platform API keys page. This is separate from ChatGPT settings.")
                instructionRow(number: 2, text: isGemini
                    ? "Select Create API key, choose or create a project, then copy the key."
                    : "Create a project API key and copy it. Add API billing or credits if your project requires them.")
                instructionRow(number: 3, text: "Paste the key below and select Validate & Connect.")

                Link(destination: isGemini
                    ? URL(string: "https://aistudio.google.com/app/apikey")!
                    : URL(string: "https://platform.openai.com/api-keys")!) {
                    Label(isGemini ? "Open Google AI Studio" : "Open OpenAI API Keys", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(14)
            .background(providerColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                Text(credentialName)
                    .font(.system(size: 13, weight: .semibold))
                HStack {
                    Group {
                        if isShowingCredential {
                            TextField(placeholder, text: $credential)
                        } else {
                            SecureField(placeholder, text: $credential)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                    Button {
                        isShowingCredential.toggle()
                    } label: {
                        Image(systemName: isShowingCredential ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)
                }
                Text("Model: \(model). Website subscriptions and browser cookies cannot authorize API requests.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            .padding(16)
            .background(Palette.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))

            if let result {
                Label(result.message, systemImage: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(result.success ? .green : .red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background((result.success ? Color.green : Color.red).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                if isCurrentlyConnected {
                    Button("Disconnect", role: .destructive) {
                        Task {
                            await AIService.shared.signOut(provider: provider, store: store)
                            credential = ""
                            result = nil
                        }
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button {
                    connect()
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Validate & Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(providerColor)
                .disabled(credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            credential = isGemini ? store.preferences.geminiApiKey : store.preferences.openAiApiKey
        }
    }

    private func connect() {
        let clean = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        isTesting = true
        result = nil
        Task {
            let test = await AIService.shared.testAPIConnection(provider: provider, apiKey: clean, model: model)
            await MainActor.run {
                isTesting = false
                result = test
                guard test.success else { return }
                if isGemini {
                    store.preferences.geminiApiKey = clean
                    store.preferences.isGeminiLoggedIn = true
                } else {
                    store.preferences.openAiApiKey = clean
                    store.preferences.isChatGptLoggedIn = true
                }
                store.preferences.aiProvider = provider
                store.showToast("\(providerName) connected securely")
                dismiss()
            }
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(providerColor, in: Circle())
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
