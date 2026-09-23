import AuraKit
import SwiftUI

@main
struct AuraInsightsApp: App {
    @NSApplicationDelegateAdaptor(InsightsDelegate.self) private var delegate
    @ViewState private var model = InsightsModel()

    var body: some Scene {
        WindowGroup("Aura Insights", id: "insights") {
            InsightsRoot()
                .environment(model)
        }
        .defaultSize(width: 1180, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Actualiser") { model.reload() }.keyboardShortcut("r")
                Divider()
                ForEach(Array(StatsPeriod.allCases.enumerated()), id: \.element) { index, period in
                    Button(period.title) { model.period = period }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
    }
}

final class InsightsDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum InsightsPage: String, CaseIterable, Identifiable {
    case overview, timeline, wrapped, apps, code, music, games, media, habits, data
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Vue d'ensemble"
        case .timeline: "Chronologie"
        case .wrapped: "Wrapped"
        case .apps: "Apps"
        case .code: "Code"
        case .music: "Musique"
        case .games: "Jeux"
        case .media: "Vidéos & web"
        case .habits: "Habitudes & records"
        case .data: "Données"
        }
    }

    var color: Color {
        switch self {
        case .overview: .purple
        case .timeline: .orange
        case .wrapped: .pink
        case .apps: .blue
        case .code: .indigo
        case .music: .pink
        case .games: .green
        case .media: .red
        case .habits: .teal
        case .data: .gray
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .timeline: "calendar"
        case .wrapped: "gift.fill"
        case .apps: "macwindow"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .music: "music.note"
        case .games: "gamecontroller.fill"
        case .media: "play.tv.fill"
        case .habits: "chart.line.uptrend.xyaxis"
        case .data: "externaldrive.fill"
        }
    }
}

struct InsightsRoot: View {
    @Environment(InsightsModel.self) private var model
    @ViewState private var page: InsightsPage? = .overview

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $page) {
                Section("Résumé") {
                    ForEach([InsightsPage.overview, .timeline, .wrapped]) { row($0) }
                }
                Section("Détails") {
                    ForEach([InsightsPage.apps, .code, .music, .games, .media, .habits]) { row($0) }
                }
                Section {
                    row(.data)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            Group {
                switch page ?? .overview {
                case .overview: OverviewPage()
                case .timeline: TimelinePage()
                case .wrapped: WrappedPage()
                case .apps: AppsPage()
                case .code: CodePage()
                case .music: MusicPage()
                case .games: GamesPage()
                case .media: MediaPage()
                case .habits: HabitsPage()
                case .data: DataPage()
                }
            }
            .navigationTitle((page ?? .overview).title)
            .navigationSubtitle(subtitle)
            .toolbar {
                if page != .timeline && page != .data {
                    ToolbarItem(placement: .principal) {
                        Picker("Période", selection: $model.period) {
                            ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
                        }
                        .nativeTabsPickerStyle()
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.reload() } label: { Label("Actualiser", systemImage: "arrow.clockwise") }
                        .help("Mis à jour à \(model.lastUpdate.formatted(date: .omitted, time: .shortened))")
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }

    private var subtitle: String {
        let i = model.stats.interval
        if model.isSingleDay { return i.start.formatted(date: .complete, time: .omitted) }
        return "\(i.start.formatted(date: .abbreviated, time: .omitted)) – \(i.end.formatted(date: .abbreviated, time: .omitted))"
    }

    private func row(_ p: InsightsPage) -> some View {
        Label {
            Text(p.title)
        } icon: {
            SettingsIcon(p.symbol, color: p.color)
        }
        .tag(p)
    }
}
