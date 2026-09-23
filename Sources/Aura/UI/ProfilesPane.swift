import SwiftUI

struct ProfilesPane: View {
    @Environment(SettingsStore.self) private var store
    @ViewState private var newName = ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach($store.settings.profiles) { $profile in
                    HStack(spacing: 10) {
                        Image(systemName: profile.symbol).frame(width: 20).foregroundStyle(Color.accentColor)
                        TextField("Nom", text: $profile.name).textFieldStyle(.plain)
                        Spacer()
                        Text(summary(profile)).font(.caption).foregroundStyle(.secondary)
                        if profile.id == store.settings.activeProfileID {
                            Text("Actif").font(.caption.bold()).foregroundStyle(.green)
                        } else {
                            Button("Activer") { store.activate(profile) }
                        }
                    }
                }
                .onDelete { store.settings.profiles.remove(atOffsets: $0) }
            } header: {
                Text("Profils")
            } footer: {
                Text("Un profil règle la priorité des sources, les sources actives, les titres, boutons, temps écoulé, branche git et la pause. Change de profil depuis la barre des menus, un raccourci clavier, un Raccourci (aura://profile/<nom>) ou automatiquement avec un mode Concentration.")
            }
            Section("Nouveau profil depuis les réglages actuels") {
                HStack {
                    TextField("Nom du profil", text: $newName)
                    Button("Enregistrer") {
                        store.saveCurrentAsProfile(named: newName.trimmingCharacters(in: .whitespaces))
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("Restaurer les profils par défaut") {
                    store.settings.profiles = PresenceProfile.presets
                }
            }
        }
    }

    private func summary(_ p: PresenceProfile) -> String {
        if p.paused { return "Présence masquée" }
        let active = p.priority.filter { !p.disabledSources.contains($0) }.map(\.title)
        return active.joined(separator: " › ")
    }
}
