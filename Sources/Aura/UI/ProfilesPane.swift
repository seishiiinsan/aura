import AuraKit
import SwiftUI

struct ProfilesPane: View {
    @Environment(SettingsStore.self) private var store
    @ViewState private var newName = ""

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                ForEach($store.settings.profiles) { $profile in
                    let active = profile.id == store.settings.activeProfileID
                    HStack(spacing: 10) {
                        SettingsIcon(profile.symbol, color: active ? .accentColor : .orange, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            TextField("Nom", text: $profile.name).textFieldStyle(.plain)
                            Text(summary(profile)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if active {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                        } else {
                            Button("Activer") { store.activate(profile) }
                        }
                    }
                    .contextMenu {
                        Button("Activer") { store.activate(profile) }
                        Button("Supprimer", role: .destructive) { store.settings.profiles.removeAll { $0.id == profile.id } }
                    }
                }
                .onDelete { store.settings.profiles.remove(atOffsets: $0) }
                .onMove { store.settings.profiles.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Profils")
            } footer: {
                Text("Un profil règle la priorité et l'activation des sources, les titres, boutons, temps écoulé, branche git et la pause. Change-le depuis la barre des menus, ⌃⌥⌘N, un lien aura://profile/<nom> ou un mode Concentration.")
            }
            FocusSection()

            Section {
                LabeledContent {
                    HStack {
                        TextField("Nom", text: $newName, prompt: Text("Mon profil"))
                            .multilineTextAlignment(.trailing)
                            .onSubmit(save)
                        Button("Enregistrer", action: save)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } label: {
                    Text("Nouveau profil")
                    Text("À partir des réglages actuels")
                }
                LabeledContent("") {
                    Button("Restaurer les profils par défaut") { store.settings.profiles = PresenceProfile.presets }
                }
            }
        }
    }

    private func save() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.saveCurrentAsProfile(named: name)
        newName = ""
    }

    private func summary(_ p: PresenceProfile) -> String {
        if p.paused { return "Présence masquée" }
        let active = p.priority.filter { !p.disabledSources.contains($0) }.map(\.title)
        return active.joined(separator: " › ")
    }
}

/// Maps macOS Focus modes to profiles.
struct FocusSection: View {
    @Environment(SettingsStore.self) private var store
    @Environment(PresenceEngine.self) private var engine
    @ViewState private var focusNames: [String] = []
    @ViewState private var readable = FocusMonitor.canRead

    var body: some View {
        Section {
            if readable {
                ForEach(focusNames, id: \.self) { focus in
                    Picker(focus, selection: Binding(
                        get: { store.settings.focusProfiles[focus] ?? "" },
                        set: { store.settings.focusProfiles[focus] = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("Ne rien changer").tag("")
                        ForEach(store.settings.profiles) { Text($0.name).tag($0.name) }
                    }
                }
                Picker("Sans Concentration", selection: Binding(
                    get: { store.settings.noFocusProfile },
                    set: { store.settings.noFocusProfile = $0 }
                )) {
                    Text("Ne rien changer").tag("")
                    ForEach(store.settings.profiles) { Text($0.name).tag($0.name) }
                }
                if let focus = engine.activeFocus {
                    LabeledContent("Concentration active") { Label(focus, systemImage: "moon.fill").foregroundStyle(.indigo) }
                }
            } else {
                IconRow(symbol: "moon.fill", color: .indigo, title: "Détection automatique",
                        subtitle: "Nécessite l'accès complet au disque.") {
                    Button("Autoriser…") { FocusMonitor.openFullDiskAccessSettings() }
                }
                IconRow(symbol: "square.2.layers.3d.fill", color: .pink, title: "Automatisation Raccourcis",
                        subtitle: "Quand une Concentration s'active → Ouvrir l'URL aura://profile/<nom>.") {
                    Button("Ouvrir Raccourcis") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                }
            }
        } header: {
            Text("Modes de Concentration")
        }
        .onAppear {
            readable = FocusMonitor.canRead
            focusNames = FocusMonitor.allFocusNames()
        }
    }
}
