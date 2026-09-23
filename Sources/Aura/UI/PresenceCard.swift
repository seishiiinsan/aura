import SwiftUI

/// A faithful-ish rendering of how the activity looks on a Discord profile.
struct PresenceCard: View {
    let snapshot: PresenceSnapshot?
    let appName: String?
    var paused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)

            if let p = snapshot?.presence, !paused {
                HStack(alignment: .center, spacing: 12) {
                    artwork(p)
                    VStack(alignment: .leading, spacing: 2) {
                        if let d = p.details {
                            Text(d).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        }
                        if let s = p.state {
                            Text(s).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if let large = p.largeText, p.type == .listening {
                            Text(large).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            timeView(p, now: ctx.date)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if !p.buttons.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(p.buttons, id: \.self) { b in
                            Text(b.label)
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.quaternary)
                        .frame(width: 72, height: 72)
                        .overlay(Image(systemName: paused ? "pause.fill" : "moon.zzz.fill").font(.title2).foregroundStyle(.secondary))
                    Text(paused ? "Aura est en pause" : "Aucune activité à afficher")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator.opacity(0.5)))
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
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(.primary).frame(width: geo.size.width * elapsed / total)
                    }
                }
                .frame(height: 4)
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
        if let url, let u = URL(string: url) {
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

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [.purple.opacity(0.6), .indigo.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol).foregroundStyle(.white.opacity(0.9))
        }
    }
}
