import SwiftUI

struct EditPlatformSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let platform: SocialPlatform
    @State private var name: String
    @State private var symbol: String
    @State private var color: String
    @State private var websiteURL: String

    private let icons = [
        ("Chat", "bubble.left.and.bubble.right.fill"),
        ("Phone", "phone.bubble.fill"),
        ("Camera", "camera.fill"),
        ("Send", "paperplane.fill"),
        ("People", "person.2.fill"),
        ("Video", "video.fill")
    ]
    private let colors = ["purple", "green", "pink", "blue", "orange"]

    init(platform: SocialPlatform) {
        self.platform = platform
        _name = State(initialValue: platform.name)
        _symbol = State(initialValue: platform.symbol)
        _color = State(initialValue: platform.color)
        _websiteURL = State(initialValue: platform.resolvedWebsiteURL?.absoluteString ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "Edit social app", subtitle: "Change how this platform appears in PINGGO.")
            labeledField("Display name", text: $name)
            labeledField("Website URL (https://…)", text: $websiteURL)
            VStack(alignment: .leading, spacing: 8) {
                Text("ICON").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
                HStack(spacing: 9) {
                    ForEach(icons, id: \.1) { icon in
                        Button { symbol = icon.1 } label: {
                            Image(systemName: icon.1)
                                .font(.system(size: 16))
                                .frame(width: 42, height: 38)
                                .background(symbol == icon.1 ? Palette.accent.opacity(0.35) : Palette.card, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .help(icon.0)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("COLOR").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
                HStack(spacing: 11) {
                    ForEach(colors, id: \.self) { option in
                        Button { color = option } label: {
                            Circle().fill(spaceColor(option))
                                .frame(width: 25, height: 25)
                                .padding(4)
                                .overlay(Circle().strokeBorder(color == option ? .white : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .help(option.capitalized)
                    }
                }
            }
            HStack {
                if !websiteURL.isEmpty && !validWebsite {
                    Text("Enter a valid HTTPS website.").font(.system(size: 11)).foregroundStyle(.orange)
                }
                if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                    !store.isPlatformNameAvailable(name, excluding: platform.id) {
                    Text("That name is already in your list.").font(.system(size: 11)).foregroundStyle(.orange)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save changes") {
                    store.updatePlatform(id: platform.id, name: name, symbol: symbol, color: color,
                                         websiteURL: websiteURL.isEmpty ? nil : websiteURL)
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(Palette.accent)
                .disabled(!store.isPlatformNameAvailable(name, excluding: platform.id) || (!websiteURL.isEmpty && !validWebsite))
            }
        }
        .padding(28)
        .frame(width: 430)
        .background(Palette.sidebar)
    }

    private var validWebsite: Bool {
        guard let url = URL(string: websiteURL), url.scheme?.lowercased() == "https" else { return false }
        return url.host != nil
    }
}
