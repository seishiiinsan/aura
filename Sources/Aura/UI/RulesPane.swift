import AppKit
import AuraKit
import SwiftUI

struct RulesPane: View {
    @Environment(SettingsStore.self) private var store
    @ViewState private var editing: AppRule.ID?

    var body: some View {
        Form {
            Section {
                if store.settings.rules.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune règle", systemImage: "slider.horizontal.3")
                    } description: {
                        Text("Personnalise, masque ou marque comme jeu n'importe quelle app.")
                    } actions: {
                        addMenu.nativeButtonStyle(prominent: true)
                    }
                } else {
                    ForEach(store.settings.rules) { rule in
                        HStack(spacing: 10) {
                            AppIconView(bundleID: rule.bundleID).frame(width: 26, height: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.appName)
                                Text(summary(rule)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Modifier…") { editing = rule.id }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = rule.id }
                        .contextMenu {
                            Button("Modifier…") { editing = rule.id }
                            Button("Dupliquer") { duplicate(rule) }
                            Divider()
                            Button("Supprimer", role: .destructive) { store.settings.rules.removeAll { $0.id == rule.id } }
                        }
                    }
                    .onDelete { store.settings.rules.remove(atOffsets: $0) }
                    .onMove { store.settings.rules.move(fromOffsets: $0, toOffset: $1) }
                }
            } header: {
                HStack {
                    Text("Règles")
                    Spacer()
                    if !store.settings.rules.isEmpty { addMenu.menuStyle(.button).buttonStyle(.borderless).fixedSize() }
                }
            } footer: {
                Text("Les règles d'une même app sont évaluées dans l'ordre : la première dont les conditions correspondent s'applique. Glisse pour réordonner.")
            }
        }
        .sheet(item: Binding(
            get: { editing.map { EditingID(id: $0) } },
            set: { editing = $0?.id }
        )) { item in
            if let index = store.settings.rules.firstIndex(where: { $0.id == item.id }) {
                RuleSheet(rule: Binding(
                    get: { store.settings.rules[index] },
                    set: { store.settings.rules[index] = $0 }
                ), onDelete: {
                    store.settings.rules.remove(at: index)
                    editing = nil
                })
            }
        }
    }

    private struct EditingID: Identifiable { let id: UUID }

    private var addMenu: some View {
        Menu {
            Section("Apps ouvertes") {
                ForEach(runningApps, id: \.bundleIdentifier) { app in
                    Button {
                        add(app)
                    } label: {
                        if let icon = app.icon { Label { Text(app.localizedName ?? "?") } icon: { Image(nsImage: icon) } }
                        else { Text(app.localizedName ?? "?") }
                    }
                }
            }
            Divider()
            Button("Choisir une app…") { pickApp() }
        } label: {
            Label("Ajouter une règle", systemImage: "plus")
        }
    }

    private func summary(_ rule: AppRule) -> String {
        var parts = [rule.mode.title]
        if !rule.conditions.isEmpty { parts.append("sous conditions") }
        if !rule.details.isEmpty { parts.append("« \(rule.details) »") }
        return parts.joined(separator: " · ")
    }

    private func duplicate(_ rule: AppRule) {
        var copy = AppRule(bundleID: rule.bundleID, appName: rule.appName)
        let id = copy.id
        copy = rule
        copy.id = id
        store.settings.rules.append(copy)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private func add(_ app: NSRunningApplication) {
        guard let id = app.bundleIdentifier else { return }
        add(bundleID: id, name: app.localizedName ?? id)
    }

    private func add(bundleID: String, name: String) {
        // Several rules per app are allowed (with different conditions); the first match wins.
        let rule = AppRule(bundleID: bundleID, appName: name)
        store.settings.rules.append(rule)
        editing = rule.id
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        add(bundleID: id, name: name)
    }
}

/// Modal editor for one rule, with the standard sheet toolbar.
struct RuleSheet: View {
    @Binding var rule: AppRule
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RuleEditor(rule: $rule)
                .navigationTitle(rule.appName)
                .toolbar {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Supprimer la règle", role: .destructive, action: onDelete)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
                    }
                }
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 560, idealHeight: 680)
    }
}

struct RuleEditor: View {
    @Binding var rule: AppRule
    @Environment(PresenceEngine.self) private var engine

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AppIconView(bundleID: rule.bundleID).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        TextField("Nom", text: $rule.appName).font(.headline).textFieldStyle(.plain)
                        Text(rule.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Picker("Comportement", selection: $rule.mode) {
                    ForEach(RuleMode.allCases) { Text($0.title).tag($0) }
                }
                if rule.mode == .customize {
                    LabeledContent("Aperçu") {
                        if let end = engine.previewEndsAt {
                            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                                Label("En ligne sur Discord · \(max(0, Int(end.timeIntervalSince(ctx.date)))) s", systemImage: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(.green)
                                    .contentTransition(.numericText())
                            }
                        } else {
                            Button {
                                engine.preview(rule)
                            } label: {
                                Label("Tester 10 s sur Discord", systemImage: "play.fill")
                            }
                            .nativeButtonStyle()
                        }
                    }
                }
            }

            ConditionsEditor(conditions: $rule.conditions)

            if rule.mode != .hide {
                Section {
                    TextField("Ligne 1 (details)", text: $rule.details, prompt: Text("Automatique"))
                    TextField("Ligne 2 (state)", text: $rule.state, prompt: Text("Automatique"))
                    TextField("Texte au survol de l'image", text: $rule.largeText, prompt: Text("Automatique"))
                    Picker("Type d'activité", selection: $rule.activityType) {
                        ForEach(ActivityTypeOverride.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Textes")
                } footer: {
                    Text("Variables : " + Template.variables.map { "{\($0)}" }.joined(separator: " ") + "  — ainsi que {details} et {state} pour réutiliser le texte automatique.")
                }

                Section {
                    TextField("URL de l'image (https://…)", text: $rule.largeImageURL, prompt: Text("Automatique (icône, pochette, jaquette…)"))
                    if !rule.largeImageURL.isEmpty {
                        RemoteImage(url: rule.largeImageURL).frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                } header: {
                    Text("Image")
                } footer: {
                    Text("Les GIF et WebP animés sont acceptés par Discord.")
                }

                Section("Bouton") {
                    TextField("Libellé (32 caractères max)", text: $rule.buttonLabel)
                    TextField("Lien (https://…)", text: $rule.buttonURL)
                }

                Section {
                    TextField("Application ID Discord dédiée", text: $rule.clientID, prompt: Text("Utiliser celle par défaut"))
                        .font(.body.monospacedDigit())
                } footer: {
                    Text("Permet d'afficher un nom différent après « Joue à » pour cette app.")
                }
            } else {
                Section {
                    Label("Rien ne sera jamais partagé quand cette app est au premier plan.", systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AppIconView: View {
    let bundleID: String

    var body: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit()
        } else {
            Image(systemName: "app.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
        }
    }
}

struct ConditionsEditor: View {
    @Binding var conditions: RuleConditions

    private static let days: [(Int, String)] = [(2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")]

    var body: some View {
        Section {
            Toggle("Seulement entre certaines heures", isOn: $conditions.useHours)
            if conditions.useHours {
                DatePicker("De", selection: minuteBinding(\.fromMinute), displayedComponents: .hourAndMinute)
                DatePicker("À", selection: minuteBinding(\.toMinute), displayedComponents: .hourAndMinute)
            }
            LabeledContent("Jours") {
                HStack(spacing: 4) {
                    ForEach(Self.days, id: \.0) { day, label in
                        let on = conditions.weekdays.contains(day)
                        Toggle(label, isOn: Binding(
                            get: { on },
                            set: { if $0 { conditions.weekdays.insert(day) } else { conditions.weekdays.remove(day) } }
                        ))
                        .toggleStyle(.button)
                        .buttonBorderShape(.circle)
                    }
                }
            }
            TextField("Le titre de la fenêtre contient…", text: $conditions.titleContains)
            Toggle("Seulement avec un écran externe branché", isOn: $conditions.requiresExternalDisplay)
        } header: {
            Text("Conditions")
        } footer: {
            Text("Aucun jour sélectionné = tous les jours. Plusieurs règles pour une même app sont évaluées dans l'ordre de la liste (glisse pour réordonner).")
        }
    }

    private func minuteBinding(_ key: WritableKeyPath<RuleConditions, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(conditions[keyPath: key] * 60)) },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                conditions[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
