import SwiftUI

struct Avatar: View {
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

struct SectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 27, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
    }
}

struct EmptyState: View {
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

@MainActor
func labeledField(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .padding(11)
            .background(Palette.background, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct AppLogo: View {
    let size: CGFloat
    var cornerRadius: CGFloat? = nil

    var body: some View {
        Group {
            if let file = Bundle.module.url(forResource: "app-logo", withExtension: "png"),
               let image = NSImage(contentsOf: file) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? (size * 0.22)))
            } else {
                Image(systemName: "square.stack.3d.up.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Palette.accent)
            }
        }
        .frame(width: size, height: size)
    }
}
