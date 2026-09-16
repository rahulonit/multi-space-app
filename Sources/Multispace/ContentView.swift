import SwiftUI

private enum Palette {
    static let background = Color(red: 0.055, green: 0.060, blue: 0.085)
    static let sidebar = Color(red: 0.080, green: 0.084, blue: 0.115)
    static let panel = Color(red: 0.105, green: 0.110, blue: 0.145)
    static let card = Color(red: 0.135, green: 0.140, blue: 0.180)
    static let muted = Color(red: 0.60, green: 0.62, blue: 0.69)
    static let accent = Color(red: 0.65, green: 0.55, blue: 1.0)
}

private func spaceColor(_ name: String) -> Color {
    switch name {
    case "green": return Color(red: 0.25, green: 0.80, blue: 0.48)
    case "pink": return Color(red: 1, green: 0.55, blue: 0.72)
    case "blue": return Color(red: 0.43, green: 0.70, blue: 1)
    case "orange": return Color(red: 1, green: 0.67, blue: 0.37)
    default: return Palette.accent
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingAddPlatform = false

    var body: some View {
        HStack(spacing: 0) {
            navigationSidebar
            mainContent
        }
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingAddPlatform) { AddPlatformSheet() }
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Multispace")
                    .font(.system(size: 20, weight: .bold))
                Text("All your social apps, one place")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 31)
            .padding(.bottom, 24)

            VStack(spacing: 4) {
                navButton("Home", symbol: "house.fill", destination: .home)
                navButton("Feed", symbol: "square.grid.2x2.fill", destination: .feed)
                navButton("Inbox", symbol: "bubble.left.and.bubble.right.fill", destination: .inbox)
            }
            .padding(.horizontal, 10)

            HStack {
                Text("SOCIAL APPS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Palette.muted)
                Spacer()
                Button { showingAddPlatform = true } label: {
                    Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .help("Add social app")
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.socialPlatforms) { platform in
                        platformButton(platform)
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                Avatar(member: store.me, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.me.name).font(.system(size: 12, weight: .semibold))
                    Text("@\(store.me.handle)").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { store.destination = .profile } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
            }
            .padding(14)
            .background(Palette.card.opacity(0.45))
        }
        .frame(width: 224)
        .background(Palette.sidebar)
    }

    private func navButton(_ title: String, symbol: String, destination: AppDestination) -> some View {
        Button { store.destination = destination } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 19)
                Text(title).font(.system(size: 13, weight: store.destination == destination ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(store.destination == destination ? .white : Palette.muted)
            .padding(.horizontal, 12)
            .frame(height: 35)
            .background(store.destination == destination ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func platformButton(_ platform: SocialPlatform) -> some View {
        let selected = store.destination == .platform(platform.id)
        return Button { store.destination = .platform(platform.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: platform.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(spaceColor(platform.color))
                    .frame(width: 19)
                Text(platform.name).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(selected ? .white : Palette.muted)
            .padding(.horizontal, 12)
            .frame(height: 37)
            .background(selected ? Palette.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch store.destination {
            case .home: HomeView()
            case .feed: FeedView()
            case .inbox: InboxView()
            case .platform(let id): PlatformView(platformID: id)
            case .channel, .conversation: ChatView(destination: store.destination)
            case .profile: ProfileView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}

private struct Avatar: View {
    let member: Member
    let size: CGFloat

    var body: some View {
        Text(member.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(spaceColor(member.color).gradient, in: RoundedRectangle(cornerRadius: size * 0.34))
    }
}

private struct SectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 27, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
    }
}

private struct HomeView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    SectionHeading(title: "Welcome back, \(store.me.name)", subtitle: "Your people and conversations are all here.")
                    Spacer()
                    Image(systemName: "sparkles").font(.system(size: 25)).foregroundStyle(Palette.accent)
                }
                .padding(.top, 36)
                VStack(alignment: .leading, spacing: 14) {
                    Text("YOUR SOCIAL APPS").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
                    ForEach(store.socialPlatforms) { platform in
                        Button { store.destination = .platform(platform.id) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: platform.symbol).font(.system(size: 19)).foregroundStyle(spaceColor(platform.color))
                                    .frame(width: 42, height: 42)
                                    .background(spaceColor(platform.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(platform.name).font(.system(size: 14, weight: .semibold))
                                    Text("Account not connected").font(.system(size: 12)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                            }
                            .padding(14)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("COMMUNITY POSTS").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
                    ForEach(store.activePosts.prefix(2)) { post in PostCard(post: post) }
                }
            }
            .padding(.horizontal, 38)
            .padding(.bottom, 36)
            .frame(maxWidth: 850)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct FeedView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SectionHeading(title: "Community feed", subtitle: "Thoughts and updates from \(store.activeSpace?.name ?? "your space")")
                    .padding(.top, 36)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        Avatar(member: store.me, size: 38)
                        Text("Share something with your space")
                            .font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    TextEditor(text: $draft)
                        .scrollContentBackground(.hidden)
                        .frame(height: 86)
                        .padding(8)
                        .background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                    HStack {
                        Text("A post is visible in this space").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Spacer()
                        Button("Publish") { store.publish(draft); draft = "" }
                            .buttonStyle(.borderedProminent).tint(Palette.accent)
                            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(18)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
                if store.activePosts.isEmpty {
                    EmptyState(symbol: "text.bubble", title: "No posts yet", subtitle: "Start the conversation in this space.")
                } else {
                    ForEach(store.activePosts) { post in PostCard(post: post) }
                }
            }
            .padding(.horizontal, 38)
            .padding(.bottom, 36)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PostCard: View {
    @EnvironmentObject private var store: AppStore
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 11) {
                Avatar(member: store.member(post.authorID) ?? store.me, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.member(post.authorID)?.name ?? "Member").font(.system(size: 13, weight: .semibold))
                    Text(post.createdAt, style: .relative).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Image(systemName: "ellipsis").foregroundStyle(Palette.muted)
            }
            Text(post.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
            Button { store.toggleLike(post.id) } label: {
                Label("\(post.likedBy.count)", systemImage: post.likedBy.contains(store.me.id) ? "heart.fill" : "heart")
                    .foregroundStyle(post.likedBy.contains(store.me.id) ? .pink : Palette.muted)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(19)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct InboxView: View {
    @EnvironmentObject private var store: AppStore

    private var matchingMembers: [Member] {
        let query = store.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.data.members }
        return store.data.members.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.handle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "Inbox", subtitle: "Direct conversations with your people")
                .padding(.top, 36)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Find a person", text: $store.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(12)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 11))
            Text("PEOPLE").font(.system(size: 11, weight: .bold)).tracking(1.5).foregroundStyle(Palette.muted)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(matchingMembers) { member in
                        Button { store.startConversation(with: member.id) } label: {
                            HStack(spacing: 13) {
                                Avatar(member: member, size: 45)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(member.name).font(.system(size: 14, weight: .semibold))
                                    Text("@\(member.handle) · \(member.status)").font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(Palette.muted)
                            }
                            .padding(14)
                            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 38)
        .padding(.bottom, 30)
        .frame(maxWidth: 780)
        .frame(maxWidth: .infinity)
    }
}

private struct ChatView: View {
    @EnvironmentObject private var store: AppStore
    let destination: AppDestination
    @State private var draft = ""

    private var title: String {
        switch destination {
        case .channel(let id): return "# " + (store.data.channels.first { $0.id == id }?.name ?? "channel")
        case .conversation(let id):
            guard let conversation = store.data.conversations.first(where: { $0.id == id }) else { return "Conversation" }
            return store.member(conversation.memberID)?.name ?? "Conversation"
        default: return "Chat"
        }
    }

    private var subtitle: String {
        switch destination {
        case .channel(let id): return store.data.channels.first { $0.id == id }?.topic ?? ""
        case .conversation: return "Direct message"
        default: return ""
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 18, weight: .bold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 27)
            .frame(height: 74)
            .background(Palette.panel)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if store.messages(for: destination).isEmpty {
                            EmptyState(symbol: "bubble.left", title: "Start a conversation", subtitle: "Say hello to get things going.")
                        }
                        ForEach(store.messages(for: destination)) { message in
                            HStack(alignment: .top, spacing: 11) {
                                Avatar(member: store.member(message.authorID) ?? store.me, size: 36)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 9) {
                                        Text(store.member(message.authorID)?.name ?? "Member")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(message.sentAt, style: .time)
                                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    }
                                    Text(message.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                                }
                                Spacer()
                            }
                            .id(message.id)
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: store.data.messages.count) { _, _ in
                    if let id = store.messages(for: destination).last?.id {
                        withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message \(title)", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(13)
                    .background(Palette.panel, in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.borderedProminent).tint(Palette.accent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
    }

    private func send() { store.send(draft, to: destination); draft = "" }
}

private struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var name = ""
    @State private var handle = ""
    @State private var status = ""
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SectionHeading(title: "Your profile", subtitle: "How you appear across your spaces")
                .padding(.top, 36)
            HStack(spacing: 17) {
                Avatar(member: store.me, size: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.me.name).font(.system(size: 18, weight: .semibold))
                    Text("@\(store.me.handle)").foregroundStyle(Palette.muted)
                }
            }
            VStack(alignment: .leading, spacing: 14) {
                labeledField("Display name", text: $name)
                labeledField("Handle", text: $handle)
                labeledField("Status", text: $status)
                HStack {
                    if saved { Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    Spacer()
                    Button("Save changes") {
                        store.updateProfile(name: name, handle: handle, status: status)
                        saved = true
                    }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                }
            }
            .padding(22)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
        .padding(.horizontal, 38)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .onAppear {
            name = store.me.name
            handle = store.me.handle
            status = store.me.status
        }
    }
}

private func labeledField(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .padding(11)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct EmptyState: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(Palette.accent)
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(45)
    }
}

private struct AddPlatformSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    private let suggestions = ["Discord", "Signal", "LinkedIn", "X", "Snapchat", "TikTok"]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(title: "Add a social app", subtitle: "Choose another platform to show in your sidebar.")
            Text("POPULAR APPS")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Palette.muted)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button(suggestion) {
                        store.addPlatform(name: suggestion)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
            }
            labeledField("Or enter an app name", text: $name)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add app") { store.addPlatform(name: name); dismiss() }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 430)
        .background(Palette.sidebar)
    }
}

private struct PlatformView: View {
    @EnvironmentObject private var store: AppStore
    let platformID: String

    var body: some View {
        let platform = store.platform(platformID)
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 17) {
                Image(systemName: platform?.symbol ?? "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(spaceColor(platform?.color ?? "purple"))
                    .frame(width: 64, height: 64)
                    .background(spaceColor(platform?.color ?? "purple").opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                SectionHeading(title: platform?.name ?? "Social app", subtitle: "Your account and conversations")
            }
            .padding(.top, 38)
            VStack(alignment: .leading, spacing: 10) {
                Label("Account not connected", systemImage: "link.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(platform?.name ?? "This app") appears in your sidebar. Account connection and message sync will be available when its supported integration is added.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
        .padding(.horizontal, 38)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }
}
