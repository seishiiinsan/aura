import AuraKit
import Charts
import SwiftUI

private let grid2 = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
private let grid4 = [GridItem(.adaptive(minimum: 170), spacing: 12)]

struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) { content }.padding(20) }
    }
}

// MARK: - Vue d'ensemble

struct OverviewPage: View {
    @Environment(InsightsModel.self) private var model

    var body: some View {
        let s = model.stats, p = model.previous
        PageScroll {
            LazyVGrid(columns: grid4, spacing: 12) {
                KPITile(title: "Temps actif", value: Format.duration(s.activeTime()), symbol: "bolt.fill", tint: .purple,
                        trend: trend(s.activeTime(), p.activeTime()))
                KPITile(title: "Jeu", value: Format.duration(s.total("game")), symbol: Kind.symbol("game"), tint: .green,
                        trend: trend(s.total("game"), p.total("game")), caption: "\(s.distinct("game") { $0.name }) jeux")
                KPITile(title: "Musique", value: Format.duration(s.total("music")), symbol: Kind.symbol("music"), tint: .pink,
                        trend: trend(s.total("music"), p.total("music")), caption: "\(s.count("music")) écoutes")
                KPITile(title: "Vidéos", value: Format.duration(s.total("video")), symbol: Kind.symbol("video"), tint: .red,
                        trend: trend(s.total("video"), p.total("video")), caption: "\(s.count("video")) vidéos")
                KPITile(title: "Apps", value: Format.duration(s.total("app")), symbol: Kind.symbol("app"), tint: .blue,
                        trend: trend(s.total("app"), p.total("app")), caption: "\(s.distinct("app") { $0.name }) apps")
                KPITile(title: "Série", value: "\(s.streaks().current) j", symbol: "flame.fill", tint: .orange,
                        caption: "record : \(s.streaks().best) j")
            }
            Card(title: model.isSingleDay ? "Heure par heure" : "Jour par jour", subtitle: "Temps par type d'activité") {
                TimeSeriesChart(buckets: s.series(byHour: model.isSingleDay), byHour: model.isSingleDay)
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                Card(title: "Répartition") {
                    DonutChart(items: Kind.all.map { (Kind.title($0), s.total($0), Kind.color($0)) }.filter { $0.1 > 0 })
                }
                Card(title: "Ta journée type", subtitle: "Activité selon l'heure") {
                    HourProfileChart(buckets: s.hourProfile(), tint: .purple)
                    HStack {
                        Label("Pic à \(s.peakHour().map { "\($0)h" } ?? "–")", systemImage: "chart.line.uptrend.xyaxis")
                        Spacer()
                        Label("\(Int((s.nightOwlRatio() * 100).rounded())) % la nuit", systemImage: "moon.stars")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                Card(title: "Top apps") { RankingList(items: s.top("app", limit: 5, label: { $0.name }), tint: .blue) }
                Card(title: "Top jeux") { RankingList(items: s.top("game", limit: 5, label: { $0.name }), tint: .green, showCount: "sessions") }
                Card(title: "Top morceaux") {
                    RankingList(items: s.topByCount("music", limit: 5, label: { $0.meta["track"] ?? $0.details }, subtitle: { $0.meta["artist"] }),
                                tint: .pink, showCount: "écoutes")
                }
                Card(title: "Top artistes") {
                    RankingList(items: s.top("music", limit: 5, label: { $0.meta["artist"] ?? $0.state }), tint: .pink, showCount: "titres")
                }
            }
        }
    }
}

// MARK: - Chronologie

struct TimelinePage: View {
    @Environment(InsightsModel.self) private var model
    @ViewState private var day = Date()

    var body: some View {
        let sessions = model.sessions(on: day)
        let start = Calendar.current.startOfDay(for: day)
        PageScroll {
            HStack {
                DatePicker("Jour", selection: $day, in: ...Date(), displayedComponents: .date).fixedSize()
                Button { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! } label: { Image(systemName: "chevron.left") }
                Button { day = min(Date(), Calendar.current.date(byAdding: .day, value: 1, to: day)!) } label: { Image(systemName: "chevron.right") }
                Button("Aujourd'hui") { day = Date() }
                Spacer()
                Text("\(sessions.count) sessions").foregroundStyle(.secondary)
            }
            Card(title: "Chronologie", subtitle: "Chaque ligne est un flux d'activité parallèle") {
                Chart(sessions) { s in
                    BarMark(
                        xStart: .value("Début", max(s.start, start)),
                        xEnd: .value("Fin", max(s.end, s.start.addingTimeInterval(60))),
                        y: .value("Flux", Kind.title(s.kind))
                    )
                    .foregroundStyle(Kind.color(s.kind))
                    .cornerRadius(3)
                }
                .chartXScale(domain: start...Calendar.current.date(byAdding: .day, value: 1, to: start)!)
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 200)
            }
            Card(title: "Détail") {
                if sessions.isEmpty {
                    Text("Aucune activité enregistrée ce jour-là.").foregroundStyle(.secondary)
                }
                ForEach(sessions.reversed()) { s in
                    HStack(spacing: 10) {
                        Image(systemName: Kind.symbol(s.kind)).foregroundStyle(Kind.color(s.kind)).frame(width: 18)
                        Artwork(url: s.image, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.details ?? s.name).lineLimit(1)
                            Text([s.name, s.state].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(s.start.formatted(date: .omitted, time: .shortened)) – \(s.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(Format.duration(s.duration)).font(.callout.monospacedDigit()).frame(width: 90, alignment: .trailing)
                    }
                    Divider()
                }
            }
        }
    }
}

// MARK: - Apps

struct AppsPage: View {
    @Environment(InsightsModel.self) private var model

    var body: some View {
        let s = model.stats
        PageScroll {
            LazyVGrid(columns: grid4, spacing: 12) {
                KPITile(title: "Temps sur les apps", value: Format.duration(s.total("app")), symbol: "macwindow", tint: .blue)
                KPITile(title: "Apps utilisées", value: "\(s.distinct("app") { $0.name })", symbol: "square.grid.2x2", tint: .blue)
                KPITile(title: "Changements d'app", value: "\(s.count("app"))", symbol: "arrow.left.arrow.right", tint: .blue,
                        caption: "session moyenne \(Format.duration(s.averageSession("app")))")
                KPITile(title: "Plus longue session", value: Format.duration(s.longest("app")?.duration(in: s.interval) ?? 0),
                        symbol: "hourglass", tint: .blue, caption: s.longest("app")?.name)
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                Card(title: "Classement des apps") { RankingList(items: s.top("app", limit: 15, label: { $0.name }), tint: .blue, showCount: "sessions") }
                VStack(spacing: 16) {
                    Card(title: "Par catégorie") {
                        let cats = s.top("app", limit: 12, label: { Kind.categoryTitles[$0.meta["category"] ?? "other"] ?? "Autre" })
                        DonutChart(items: cats.enumerated().map { ($0.element.label, $0.element.seconds, palette[$0.offset % palette.count]) })
                    }
                    Card(title: "Quand tu utilises ton Mac") { HeatmapChart(cells: s.heatmap("app"), tint: .blue) }
                }
            }
            Card(title: "Apps jour par jour") {
                TimeSeriesChart(buckets: topGroupSeries(s, kind: "app", limit: 6) { $0.name }, byHour: model.isSingleDay,
                                colorFor: colorForLabel, labelFor: { $0 })
            }
        }
    }
}

let palette: [Color] = [.blue, .purple, .pink, .orange, .green, .teal, .indigo, .yellow, .mint, .red, .cyan, .brown]

private func colorForLabel(_ label: String) -> Color {
    label == "Autres" ? .gray : palette[abs(label.hashValue) % palette.count]
}

/// Series limited to the top N groups, the rest merged into "Autres".
func topGroupSeries(_ s: Stats, kind: String, limit: Int, byHour: Bool = false, _ key: @escaping (HistorySession) -> String) -> [TimeBucket] {
    let top = Set(s.top(kind, limit: limit, label: key).map(\.label))
    return s.series(kind, byHour: byHour) { top.contains(key($0)) ? key($0) : "Autres" }
}

// MARK: - Code

struct CodePage: View {
    @Environment(InsightsModel.self) private var model

    var body: some View {
        let s = model.stats
        let coding = Stats(sessions: s.sessions.filter { $0.kind == "app" && $0.meta["category"] == "coding" }, interval: s.interval)
        PageScroll {
            LazyVGrid(columns: grid4, spacing: 12) {
                KPITile(title: "Temps de code", value: Format.duration(coding.total("app")), symbol: "chevron.left.forwardslash.chevron.right", tint: .indigo,
                        trend: trend(coding.total("app"), Stats(sessions: model.previous.sessions.filter { $0.meta["category"] == "coding" }, interval: model.previous.interval).total("app")))
                KPITile(title: "Projets", value: "\(coding.distinct("app") { $0.meta["project"] })", symbol: "folder.fill", tint: .indigo)
                KPITile(title: "Langages", value: "\(coding.distinct("app") { $0.meta["language"] })", symbol: "curlybraces", tint: .indigo)
                KPITile(title: "Fichiers édités", value: "\(coding.distinct("app") { $0.meta["file"] })", symbol: "doc.text", tint: .indigo)
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                Card(title: "Langages") {
                    let langs = coding.top("app", limit: 8, label: { $0.meta["language"] })
                    DonutChart(items: langs.enumerated().map { ($0.element.label, $0.element.seconds, palette[$0.offset % palette.count]) })
                }
                Card(title: "Éditeurs") { RankingList(items: coding.top("app", limit: 6, label: { $0.name }), tint: .indigo) }
                Card(title: "Projets") { RankingList(items: coding.top("app", limit: 10, label: { $0.meta["project"] }), tint: .indigo, showCount: "sessions") }
                Card(title: "Branches") {
                    RankingList(items: coding.top("app", limit: 10, label: { $0.meta["branch"] }, subtitle: { $0.meta["project"] }), tint: .indigo)
                }
                Card(title: "Fichiers les plus travaillés") {
                    RankingList(items: coding.top("app", limit: 10, label: { $0.meta["file"] }, subtitle: { $0.meta["project"] }), tint: .indigo)
                }
                Card(title: "Tes heures de code") { HeatmapChart(cells: coding.heatmap("app"), tint: .indigo) }
            }
        }
    }
}

// MARK: - Musique

struct MusicPage: View {
    @Environment(InsightsModel.self) private var model

    var body: some View {
        let s = model.stats
        PageScroll {
            LazyVGrid(columns: grid4, spacing: 12) {
                KPITile(title: "Écoute", value: Format.duration(s.total("music")), symbol: "headphones", tint: .pink,
                        trend: trend(s.total("music"), model.previous.total("music")))
                KPITile(title: "Titres écoutés", value: "\(s.count("music"))", symbol: "music.note.list", tint: .pink,
                        caption: "\(s.distinct("music") { $0.meta["track"] }) différents")
                KPITile(title: "Artistes", value: "\(s.distinct("music") { $0.meta["artist"] })", symbol: "person.2.fill", tint: .pink,
                        caption: "\(newArtists(s)) nouveaux")
                KPITile(title: "Albums", value: "\(s.distinct("music") { $0.meta["album"] })", symbol: "square.stack.fill", tint: .pink)
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                Card(title: "Top titres", subtitle: "par nombre d'écoutes") {
                    RankingList(items: s.topByCount("music", limit: 10, label: { $0.meta["track"] ?? $0.details }, subtitle: { $0.meta["artist"] }),
                                tint: .pink, showCount: "écoutes")
                }
                Card(title: "Top artistes", subtitle: "par temps d'écoute") {
                    RankingList(items: s.top("music", limit: 10, label: { $0.meta["artist"] ?? $0.state }), tint: .pink, showCount: "titres")
                }
                Card(title: "Top albums") {
                    RankingList(items: s.top("music", limit: 8, label: { $0.meta["album"].flatMap { $0.isEmpty ? nil : $0 } }, subtitle: { $0.meta["artist"] }), tint: .pink)
                }
                Card(title: "Lecteurs") {
                    let players = s.top("music", limit: 6, label: { $0.meta["player"] ?? $0.name })
                    DonutChart(items: players.enumerated().map { ($0.element.label, $0.element.seconds, palette[($0.offset + 2) % palette.count]) })
                }
                Card(title: "Quand tu écoutes") { HourProfileChart(buckets: s.hourProfile("music"), tint: .pink) }
                Card(title: "Semaine d'écoute") { HeatmapChart(cells: s.heatmap("music"), tint: .pink) }
            }
        }
    }

    /// Artists heard in this period but never in the previous one.
    private func newArtists(_ s: Stats) -> Int {
        let before = Set(model.previous.filtered("music").compactMap { $0.meta["artist"] })
        return Set(s.filtered("music").compactMap { $0.meta["artist"] }).subtracting(before).count
    }
}

// MARK: - Jeux

struct GamesPage: View {
    @Environment(InsightsModel.self) private var model

    var body: some View {
        let s = model.stats
        PageScroll {
            LazyVGrid(columns: grid4, spacing: 12) {
                KPITile(title: "Temps de jeu", value: Format.duration(s.total("game")), symbol: "gamecontroller.fill", tint: .green,
                        trend: trend(s.total("game"), model.previous.total("game")))
                KPITile(title: "Jeux", value: "\(s.distinct("game") { $0.name })", symbol: "square.grid.3x3.fill", tint: .green)
                KPITile(title: "Sessions", value: "\(s.count("game"))", symbol: "play.circle", tint: .green,
                        caption: "moyenne \(Format.duration(s.averageSession("game")))")
                KPITile(title: "Plus longue partie", value: Format.duration(s.longest("game")?.duration(in: s.interval) ?? 0),
                        symbol: "trophy.fill", tint: .green, caption: s.longest("game")?.name)
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                Card(title: "Tes jeux") { RankingList(items: s.top("game", limit: 12, label: { $0.name }), tint: .green, showCount: "sessions") }
                VStack(spacing: 16) {
                    Card(title: "Plateformes") {
                        let platforms = s.top("game", limit: 6, label: { $0.meta["platform"] ?? "macOS" })
                        DonutChart(items: platforms.enumerated().map { ($0.element.label, $0.element.seconds, palette[($0.offset + 4) % palette.count]) })
                    }
                    Card(title: "Quand tu joues") { HeatmapChart(cells: s.heatmap("game"), tint: .green) }
                }
            }
            Card(title: "Jeux jour par jour") {
                TimeSeriesChart(buckets: topGroupSeries(s, kind: "game", limit: 6, byHour: model.isSingleDay) { $0.name },
                                byHour: model.isSingleDay, colorFor: colorForLabel, labelFor: { $0 })
            }
        }
    }
}

// MARK: - Vidéos & web

struct MediaPage: View {
    @Environment(InsightsModel.self) private var model

    var body: some View {
        let s = model.stats
        let web = Stats(sessions: s.sessions.filter { $0.kind == "app" && $0.meta["site"] != nil }, interval: s.interval)
        PageScroll {
            LazyVGrid(columns: grid4, spacing: 12) {
                KPITile(title: "Vidéos & streams", value: Format.duration(s.total("video")), symbol: "play.tv.fill", tint: .red,
                        trend: trend(s.total("video"), model.previous.total("video")))
                KPITile(title: "Vidéos vues", value: "\(s.distinct("video") { $0.details })", symbol: "film.stack", tint: .red)
                KPITile(title: "Navigation web", value: Format.duration(web.total("app")), symbol: "globe", tint: .teal)
                KPITile(title: "Sites visités", value: "\(web.distinct("app") { $0.meta["site"] })", symbol: "safari", tint: .teal)
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                Card(title: "Services vidéo") { RankingList(items: s.top("video", limit: 8, label: { $0.meta["site"] ?? $0.name }), tint: .red) }
                Card(title: "Chaînes & créateurs") {
                    RankingList(items: s.top("video", limit: 8, label: { $0.meta["channel"] ?? $0.state }), tint: .red, showCount: "vidéos")
                }
                Card(title: "Vidéos les plus regardées") {
                    RankingList(items: s.top("video", limit: 10, label: { $0.details }, subtitle: { $0.meta["channel"] }), tint: .red)
                }
                Card(title: "Sites web") { RankingList(items: web.top("app", limit: 10, label: { $0.meta["site"] }), tint: .teal, showCount: "visites") }
            }
        }
    }
}

// MARK: - Habitudes & records

struct HabitsPage: View {
    @Environment(InsightsModel.self) private var model
    private let dayNames = ["", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

    var body: some View {
        let s = model.stats
        let weekdays = s.weekdayProfile()
        let busiest = s.busiestDay()
        let longest = s.longest()
        PageScroll {
            LazyVGrid(columns: grid4, spacing: 12) {
                KPITile(title: "Premier signe de vie", value: timeString(s.averageFirstActivity()), symbol: "sunrise.fill", tint: .orange, caption: "en moyenne")
                KPITile(title: "Dernière activité", value: timeString(s.averageLastActivity()), symbol: "moon.fill", tint: .indigo, caption: "en moyenne")
                KPITile(title: "Jours actifs", value: "\(s.activeDays().count)", symbol: "calendar", tint: .purple,
                        caption: "série record \(s.streaks().best) j")
                KPITile(title: "Temps absent", value: Format.duration(s.total("idle")), symbol: "moon.zzz.fill", tint: .gray)
                KPITile(title: "Journée record", value: busiest.map { Format.duration($0.seconds) } ?? "–", symbol: "star.fill", tint: .yellow,
                        caption: busiest?.date.formatted(date: .abbreviated, time: .omitted))
                KPITile(title: "Session record", value: longest.map { Format.duration($0.duration(in: s.interval)) } ?? "–",
                        symbol: "stopwatch.fill", tint: .mint, caption: longest?.details ?? longest?.name)
                KPITile(title: "Oiseau de nuit", value: "\(Int((s.nightOwlRatio() * 100).rounded())) %", symbol: "moon.stars.fill", tint: .indigo,
                        caption: "entre 22h et 5h")
                KPITile(title: "Heure de pointe", value: s.peakHour().map { "\($0)h" } ?? "–", symbol: "chart.line.uptrend.xyaxis", tint: .purple)
            }
            Card(title: "Carte de chaleur", subtitle: "Toutes activités, par jour de semaine et par heure") {
                HeatmapChart(cells: s.heatmap(), tint: .purple)
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                Card(title: "Jours de la semaine") {
                    Chart((1...7).map { ($0, weekdays[$0] ?? 0) }, id: \.0) { day, seconds in
                        BarMark(x: .value("Jour", String(dayNames[day].prefix(3))), y: .value("Heures", seconds.hoursValue))
                            .foregroundStyle(.purple.gradient).cornerRadius(4)
                    }
                    .frame(height: 180)
                }
                Card(title: "Activité par heure et par type") {
                    Chart {
                        ForEach(Kind.all, id: \.self) { kind in
                            ForEach(Array(s.hourProfile(kind).enumerated()), id: \.offset) { i, b in
                                LineMark(x: .value("Heure", i), y: .value("Heures", b.seconds.hoursValue))
                                    .foregroundStyle(by: .value("Type", Kind.title(kind)))
                                    .interpolationMethod(.catmullRom)
                            }
                        }
                    }
                    .chartForegroundStyleScale(domain: Kind.all.map(Kind.title), range: Kind.all.map(Kind.color))
                    .frame(height: 180)
                }
            }
        }
    }
}

// MARK: - Wrapped

struct WrappedPage: View {
    @Environment(InsightsModel.self) private var model

    var body: some View {
        let s = model.stats
        let topApp = s.top("app", limit: 1, label: { $0.name }).first
        let topGame = s.top("game", limit: 1, label: { $0.name }).first
        let topArtist = s.top("music", limit: 1, label: { $0.meta["artist"] }).first
        let topTrack = s.topByCount("music", limit: 1, label: { $0.meta["track"] }, subtitle: { $0.meta["artist"] }).first
        let topLang = s.top("app", limit: 1, label: { $0.meta["language"] }).first
        PageScroll {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ton Aura Wrapped").font(.system(size: 40, weight: .heavy, design: .rounded))
                Text(model.period.title).font(.title3).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: grid2, spacing: 16) {
                WrappedCard(emoji: "⚡️", title: "Temps passé sur ton Mac", value: Format.duration(s.activeTime()),
                            colors: [.purple, .indigo])
                WrappedCard(emoji: "💻", title: "Ton app n°1", value: topApp?.label ?? "–",
                            detail: topApp.map { Format.duration($0.seconds) }, image: topApp?.image, colors: [.blue, .cyan])
                WrappedCard(emoji: "🎮", title: "Ton jeu n°1", value: topGame?.label ?? "Aucun jeu",
                            detail: topGame.map { "\(Format.duration($0.seconds)) · \($0.count) sessions" }, image: topGame?.image, colors: [.green, .mint])
                WrappedCard(emoji: "🎧", title: "Ton artiste n°1", value: topArtist?.label ?? "–",
                            detail: topArtist.map { Format.duration($0.seconds) }, image: topArtist?.image, colors: [.pink, .orange])
                WrappedCard(emoji: "🔁", title: "Le titre en boucle", value: topTrack?.label ?? "–",
                            detail: topTrack.map { "\($0.subtitle ?? "") · \($0.count) écoutes" }, image: topTrack?.image, colors: [.red, .pink])
                WrappedCard(emoji: "🧑‍💻", title: "Ton langage", value: topLang?.label ?? "–",
                            detail: topLang.map { Format.duration($0.seconds) }, image: topLang?.image, colors: [.indigo, .purple])
                WrappedCard(emoji: s.nightOwlRatio() > 0.2 ? "🦉" : "🌅", title: "Ton profil",
                            value: s.nightOwlRatio() > 0.2 ? "Oiseau de nuit" : "Lève-tôt",
                            detail: "pic d'activité à \(s.peakHour().map { "\($0)h" } ?? "–")", colors: [.indigo, .black])
                WrappedCard(emoji: "🔥", title: "Plus longue série", value: "\(s.streaks().best) jours",
                            detail: "série actuelle : \(s.streaks().current) j", colors: [.orange, .red])
            }
        }
    }
}

struct WrappedCard: View {
    let emoji: String
    let title: String
    let value: String
    var detail: String? = nil
    var image: String? = nil
    let colors: [Color]

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(emoji).font(.system(size: 34))
                Text(title).font(.callout.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                Text(value).font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                if let detail { Text(detail).font(.callout).foregroundStyle(.white.opacity(0.8)).lineLimit(1) }
            }
            Spacer(minLength: 0)
            if let image { Artwork(url: image, size: 84).shadow(radius: 8) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
    }
}

// MARK: - Données

struct DataPage: View {
    @Environment(InsightsModel.self) private var model
    @ViewState private var confirmDelete = false

    var body: some View {
        Form {
            Section("Base de données") {
                LabeledContent("Emplacement", value: HistoryStore.databaseURL.path)
                LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: model.databaseSize, countStyle: .file))
                LabeledContent("Premier enregistrement", value: model.firstDate?.formatted(date: .long, time: .shortened) ?? "–")
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([HistoryStore.databaseURL]) }
            }
            Section("Exporter") {
                Button("Exporter en CSV…") { save(model.exportCSV(), name: "aura-historique.csv") }
                Button("Exporter en JSON…") { if let d = model.exportJSON() { save(d, name: "aura-historique.json") } }
            }
            Section("Supprimer") {
                Button("Effacer l'historique de la période « \(model.period.title) »") {
                    model.delete(from: model.stats.interval.start, to: model.stats.interval.end)
                }
                Button("Tout effacer…", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Effacer tout l'historique ?", isPresented: $confirmDelete) {
            Button("Tout effacer", role: .destructive) { model.deleteAll() }
        } message: {
            Text("Cette action est définitive.")
        }
    }

    private func save(_ data: Data, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}
