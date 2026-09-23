import AuraKit
import SwiftUI

/// A faithful-ish rendering of how the activity looks on a Discord profile.
struct PresenceCard: View {
    enum Chrome { case none, surface, glass }

    let snapshot: PresenceSnapshot?
    let appName: String?
    var paused = false
    /// Background: none inside a Form row, a content surface, or Liquid Glass in floating panels.
    var chrome: Chrome = .surface

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let p = snapshot?.presence, !paused {
                HStack(alignment: .center, spacing: 12) {
                    artwork(p)
                    VStack(alignment: .leading, spacing: 2) {
                        if let d = p.details {
                            Text(d).font(.headline).lineLimit(1)
                                .contentTransition(.opacity)
                        }
                        if let s = p.state {
                            Text(s).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let large = p.largeText, p.type == .listening {
                            Text(large).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            timeView(p, now: ctx.date)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !p.buttons.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(p.buttons, id: \.self) { b in
                            Link(destination: URL(string: b.url) ?? URL(string: "https://discord.com")!) {
                                Text(b.label).font(.callout.weight(.medium)).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: 72, height: 72)
                        .overlay(Image(systemName: paused ? "pause.fill" : "moon.zzz.fill").font(.title2).foregroundStyle(.secondary))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(paused ? "Diffusion en pause" : "Aucune activité").font(.headline)
                        Text(paused ? "Ta présence Discord est masquée." : "Ouvre un jeu, une musique ou une app.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardChrome(chrome: chrome))
        .animation(.smooth, value: snapshot?.presence.details)
    }

    private var header: String {
        guard let p = snapshot?.presence, !paused else { return "Activité" }
        let name = appName ?? snapshot?.sourceApp ?? "Aura"
        return "\(p.type.label) \(name)"
    }

    @ViewBuilder
    private func artwork(_ p: RichPresence) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RemoteImage(url: p.largeImage, symbol: snapshot?.kind?.symbol ?? "sparkles")
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .help(p.largeText ?? "")
            if let small = p.smallImage {
                RemoteImage(url: small, symbol: "circle.fill")
                    .frame(width: 24, height: 24)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.background, lineWidth: 3))
                    .offset(x: 6, y: 6)
                    .help(p.smallText ?? "")
            }
        }
    }

    @ViewBuilder
    private func timeView(_ p: RichPresence, now: Date) -> some View {
        if let start = p.start, let end = p.end, end > start {
            let total = end.timeIntervalSince(start)
            let elapsed = min(max(0, now.timeIntervalSince(start)), total)
            VStack(spacing: 2) {
                ProgressView(value: elapsed, total: total)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                HStack {
                    Text(Self.format(elapsed))
                    Spacer()
                    Text(Self.format(total))
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } else if let start = p.start {
            Text("\(Self.format(now.timeIntervalSince(start))) écoulé")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.green)
        }
    }

    static func format(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// `AsyncImage` with a neutral placeholder.
struct RemoteImage: View {
    let url: String?
    var symbol = "photo"

    var body: some View {
        if let url, let u = URL(string: url), Self.isAnimated(url) {
            AnimatedRemoteImage(url: u)
        } else if let url, let u = URL(string: url) {
            AsyncImage(url: u, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholder
                }
            }
        } else {
            placeholder
        }
    }

    static func isAnimated(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains(".gif") || lower.contains(".webp") || lower.contains(".apng")
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
        }
    }
}

private struct CardChrome: ViewModifier {
    let chrome: PresenceCard.Chrome

    func body(content: Content) -> some View {
        switch chrome {
        case .none:
            content.padding(.vertical, 4)
        case .surface:
            content.contentSurface(cornerRadius: 14, padding: 14)
        case .glass:
            content
                .padding(14)
                .nativeGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
