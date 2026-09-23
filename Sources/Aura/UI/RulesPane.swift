import AppKit
import SwiftUI

struct RulesPane: View {
    @Environment(SettingsStore.self) private var store
    @ViewState private var selection: AppRule.ID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.settings.rules) { rule in
                        HStack(spacing: 8) {
                            AppIconView(bundleID: rule.bundleID).frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.appName).lineLimit(1)
                                Text(rule.mode.title + (rule.conditions.isEmpty ? "" : " · sous conditions"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(rule.id)
                    }
                    .onDelete { store.settings.rules.remove(atOffsets: $0) }
                    .onMove { store.settings.rules.move(fromOffsets: $0, toOffset: $1) }
                }
                .overlay {
                    if store.settings.rules.isEmpty {
                        ContentUnavailableView("Aucune règle", systemImage: "slider.horizontal.3",
                                               description: Text("Ajoute une app pour personnaliser, masquer ou marquer comme jeu."))
                    }
                }
                Divider()
                HStack(spacing: 4) {
                    Menu {
                        Section("Apps ouvertes") {
                            ForEach(runningApps, id: \.bundleIdentifier) { app in
                                Button(app.localizedName ?? app.bundleIdentifier ?? "?") { add(app) }
                            }
                        }
                        Divider()
                        Button("Choisir une app…") { pickApp() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Button {
                        if let selection { store.settings.rules.removeAll { $0.id == selection } }
                        selection = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(selection == nil)
                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            Group {
                if let index = store.settings.rules.firstIndex(where: { $0.id == selection }) {
                    RuleEditor(rule: Binding(
                        get: { store.settings.rules[index] },
                        set: { store.settings.rules[index] = $0 }
                    ))
                    .id(selection)
                } else {
                    ContentUnavailableView("Sélectionne une règle", systemImage: "hand.point.left")
                }
            }
            .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
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
        selection = rule.id
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

struct RuleEditor: View {
    @Binding var rule: AppRule

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    AppIconView(bundleID: rule.bundleID).frame(width: 40, height: 40)
                    VStack(alignment: .leading) {
                        TextField("Nom", text: $rule.appName).font(.headline).textFieldStyle(.plain)
                        Text(rule.bundleID).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Picker("Comportement", selection: $rule.mode) {
                    ForEach(RuleMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
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
                        RemoteImage(url: rule.largeImageURL).frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
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
                HStack {
                    DatePicker("De", selection: minuteBinding(\.fromMinute), displayedComponents: .hourAndMinute)
                    DatePicker("à", selection: minuteBinding(\.toMinute), displayedComponents: .hourAndMinute)
                }
            }
            HStack(spacing: 6) {
                Text("Jours")
                Spacer()
                ForEach(Self.days, id: \.0) { day, label in
                    let on = conditions.weekdays.contains(day)
                    Button(label) {
                        if on { conditions.weekdays.remove(day) } else { conditions.weekdays.insert(day) }
                    }
                    .buttonStyle(.bordered)
                    .tint(on ? .accentColor : .secondary)
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
