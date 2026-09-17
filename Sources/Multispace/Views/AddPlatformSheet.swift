import SwiftUI

struct AddPlatformSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var mode: AddMode = .browse
    @State private var selectedID: String?
    @State private var name = ""
    @State private var websiteURL = ""

    private enum AddMode: String, CaseIterable { case browse = "Browse apps", custom = "Custom website" }

    private var suggestions: [SocialPlatform] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (SocialPlatform.defaults + SocialPlatform.suggestions).filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || ($0.resolvedWebsiteURL?.host?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedPlatform: SocialPlatform? {
        suggestions.first { $0.id == selectedID } ?? suggestions.first
    }

    private func isInstalled(_ platform: SocialPlatform) -> Bool {
        store.socialPlatforms.contains {
            $0.id == platform.id || $0.name.localizedCaseInsensitiveCompare(platform.name) == .orderedSame
        }
    }

    private var validWebsite: Bool {
        guard let parts = URLComponents(string: websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, host.contains("."),
              parts.user == nil, parts.password == nil else { return false }
        return true
    }

    private var validCustomName: Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.isPlatformNameAvailable(clean) &&
            !(SocialPlatform.defaults + SocialPlatform.suggestions).contains {
                $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "plus.app.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Palette.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Add a social app").font(.system(size: 24, weight: .bold))
                    Text("Choose a platform or connect another HTTPS website.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .accessibilityLabel("Close")
            }
            .padding(24)

            Picker("Add mode", selection: $mode) {
                ForEach(AddMode.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            if mode == .browse { browseContent }
            else { customContent }

            Divider()
            HStack(spacing: 12) {
                Text(mode == .browse ? "Accounts are added after opening the platform." : "Your website opens in a separate in-app session.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if mode == .browse {
                    Button(selectedPlatform.map { isInstalled($0) ? "Open app" : "Add app" } ?? "Add app") {
                        guard let selectedPlatform else { return }
                        store.addPlatform(name: selectedPlatform.name)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                    .disabled(selectedPlatform == nil)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Add website") {
                        store.addPlatform(name: name, websiteURL: websiteURL.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                    .disabled(!validCustomName || !validWebsite)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 600)
        .background(Palette.sidebar)
    }

    private var browseContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search platforms", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(Palette.muted)
                        .accessibilityLabel("Clear search")
                }
            }
            .padding(12)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            Text("PLATFORMS")
                .font(.system(size: 10, weight: .bold)).tracking(1.5)
                .foregroundStyle(Palette.muted)
            ScrollView {
                if suggestions.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: "No platforms found",
                               subtitle: "Try another name, or use Custom website.")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(suggestions) { platform in
                            Button { selectedID = platform.id } label: {
                                HStack(spacing: 11) {
                                    PlatformLogo(platform: platform, size: 30)
                                        .frame(width: 36, height: 36)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(platform.name).font(.system(size: 13, weight: .semibold))
                                        Text(isInstalled(platform) ? "Already added" : platform.resolvedWebsiteURL?.host ?? "Website")
                                            .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if selectedPlatform?.id == platform.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                                    }
                                }
                                .padding(11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedPlatform?.id == platform.id ? Palette.accent.opacity(0.16) : Palette.panel,
                                            in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedPlatform?.id == platform.id ? Palette.accent.opacity(0.7) : .clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(height: 250)
            if let selectedPlatform {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(Palette.accent)
                    Text("\(selectedPlatform.name) opens \(selectedPlatform.resolvedWebsiteURL?.host ?? "its website") inside PINGGO. Sign in there with the platform’s own login.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private var customContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            labeledField("Display name", text: $name)
            labeledField("HTTPS website URL", text: $websiteURL)
            if !name.isEmpty && !validCustomName {
                Label("Choose another name, or select a listed platform in Browse apps.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange).font(.system(size: 11))
            }
            if !websiteURL.isEmpty && !validWebsite {
                Label("Enter a full HTTPS address, such as https://example.com.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange).font(.system(size: 11))
            }
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 22)).foregroundStyle(Palette.accent)
                    .frame(width: 44, height: 44)
                    .background(Palette.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    Text(name.isEmpty ? "Your website" : name).font(.system(size: 13, weight: .semibold))
                    Text(validWebsite ? (URL(string: websiteURL)?.host ?? websiteURL) : "A secure website is required")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .padding(14)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(height: 360)
    }
}
