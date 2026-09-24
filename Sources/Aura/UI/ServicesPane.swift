import AuraKit
import SwiftUI

/// Optional online services that enrich the presence. Keys live in the Keychain.
struct ServicesPane: View {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine
    @ViewState private var steamKey = Keychain.get(SecretKey.steamAPI) ?? ""
    @ViewState private var gridKey = Keychain.get(SecretKey.steamGridDB) ?? ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                IconRow(symbol: "square.grid.3x3.fill", color: .blue, title: "SteamGridDB",
                        subtitle: "Jaquettes carrées de la communauté pour quasiment tous les jeux.") {
                    StatusBadge(on: !gridKey.isEmpty)
                }
                SecureField("Clé API", text: $gridKey, prompt: Text("Non définie"))
                    .multilineTextAlignment(.trailing)
                    .onChange(of: gridKey) { _, key in
                        Keychain.set(key.trimmingCharacters(in: .whitespaces), for: SecretKey.steamGridDB)
                        engine.configureArtwork()
                        engine.scheduleRecompute()
                    }
                LabeledContent("") {
                    Link("Obtenir une clé gratuite", destination: URL(string: "https://www.steamgriddb.com/profile/preferences/api")!)
                }
            } footer: {
                Text("Prioritaires sur les autres visuels quand une clé est renseignée. Les clés sont stockées dans le trousseau macOS.")
            }

            Section {
                IconRow(symbol: "app.dashed", color: .purple, title: "Icônes d'apps hébergées",
                        subtitle: "Les vraies icônes macOS, servies depuis GitHub.") {
                    StatusBadge(on: !store.settings.iconHost.isEmpty)
                }
                TextField("URL de base", text: $store.settings.iconHost)
                    .font(.callout.monospaced())
                    .multilineTextAlignment(.trailing)
                LabeledContent("") {
                    Button("Rétablir le dépôt Aura") { store.settings.iconHost = HostedIcons.defaultBase }
                }
            } footer: {
                Text("Aura affiche les vraies icônes macOS publiées dans le dépôt (dossier assets/icons). Pour ajouter les tiennes : `swift scripts/export-icons.swift <bundle.id>` dans ton fork, puis indique son URL raw ici. Laisse vide pour désactiver.")
            }
            Section {
                IconRow(symbol: "gamecontroller.fill", color: .gray, title: "Steam",
                        subtitle: "Statut détaillé et parties sur Steam Deck ou PC.") {
                    StatusBadge(on: engine.steamStatus != nil, onText: "En jeu", offText: steamKey.isEmpty ? "Désactivé" : "Connecté")
                }
                TextField("Compte", text: $store.settings.steamAccount, prompt: Text("SteamID64 ou nom de profil"))
                    .multilineTextAlignment(.trailing)
                SecureField("Clé API Web", text: $steamKey, prompt: Text("Non définie"))
                    .multilineTextAlignment(.trailing)
                    .onChange(of: steamKey) { _, key in
                        Keychain.set(key.trimmingCharacters(in: .whitespaces), for: SecretKey.steamAPI)
                        Task { await engine.refreshSteam() }
                    }
                if let status = engine.steamStatus {
                    LabeledContent("Partie en cours", value: status.richPresence.map { "\(status.gameName) — \($0)" } ?? status.gameName)
                }
                LabeledContent("") {
                    Link("Obtenir une clé API Steam", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
                }
            } footer: {
                Text("Ton profil Steam doit être public.")
            }
        }
    }
}

struct StatusBadge: View {
    let on: Bool
    var onText = "Activé"
    var offText = "Désactivé"

    var body: some View {
        HStack(spacing: 5) {
            StatusDot(on ? .green : .secondary.opacity(0.5))
            Text(on ? onText : offText).font(.callout).foregroundStyle(.secondary)
        }
    }
}
