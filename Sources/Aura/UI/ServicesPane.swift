import SwiftUI

/// Optional online services that enrich the presence. Keys live in the Keychain.
struct ServicesPane: View {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine
    @ViewState private var steamKey = Keychain.get(SecretKey.steamAPI) ?? ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                TextField("SteamID64 ou nom de profil personnalisé", text: $store.settings.steamAccount)
                SecureField("Clé API Web Steam", text: $steamKey)
                    .onChange(of: steamKey) { _, key in
                        Keychain.set(key.trimmingCharacters(in: .whitespaces), for: SecretKey.steamAPI)
                        Task { await engine.refreshSteam() }
                    }
                if let status = engine.steamStatus {
                    Label("En jeu sur Steam : \(status.gameName)\(status.richPresence.map { " — \($0)" } ?? "")", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Link("Obtenir une clé API Steam →", destination: URL(string: "https://steamcommunity.com/dev/apikey")!)
            } header: {
                Text("Steam")
            } footer: {
                Text("Affiche le statut détaillé de ta partie (mode, carte, chapitre…) et tes parties lancées sur un autre appareil (Steam Deck, PC). Ton profil Steam doit être public. La clé est stockée dans le trousseau macOS.")
            }
        }
    }
}
