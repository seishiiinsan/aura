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
            FocusSection()

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
                if let focus = engine.activeFocus { Label("Concentration active : \(focus)", systemImage: "moon.fill").foregroundStyle(.indigo) }
            } else {
                HStack {
                    Text("Pour détecter automatiquement ta Concentration, donne à Aura l'« Accès complet au disque ».")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Ouvrir") { FocusMonitor.openFullDiskAccessSettings() }
                }
                Button("Ou créer une automatisation dans Raccourcis") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                }
            }
        } header: {
            Text("Modes de Concentration")
        } footer: {
            Text("Sans accès complet au disque : app Raccourcis › Automatisation › « Quand <Concentration> s'active » › Ouvrir l'URL aura://profile/Discret.")
        }
        .onAppear {
            readable = FocusMonitor.canRead
            focusNames = FocusMonitor.allFocusNames()
        }
    }
}
