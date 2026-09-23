import Carbon.HIToolbox
import Foundation

/// System-wide keyboard shortcuts via Carbon's RegisterEventHotKey (no permission required).
@MainActor
final class HotKeys {
    static let shared = HotKeys()

    struct Binding: Sendable {
        var keyCode: UInt32
        var label: String
        var action: HotKeyAction
    }

    enum HotKeyAction: String, CaseIterable, Sendable {
        case togglePause, nextProfile, openMain, cycleSource
    }

    /// ⌃⌥⌘ + key.
    static let bindings: [Binding] = [
        Binding(keyCode: UInt32(kVK_ANSI_P), label: "⌃⌥⌘P", action: .togglePause),
        Binding(keyCode: UInt32(kVK_ANSI_N), label: "⌃⌥⌘N", action: .nextProfile),
        Binding(keyCode: UInt32(kVK_ANSI_A), label: "⌃⌥⌘A", action: .openMain),
        Binding(keyCode: UInt32(kVK_ANSI_S), label: "⌃⌥⌘S", action: .cycleSource),
    ]

    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false
    var onAction: ((HotKeyAction) -> Void)?

    func setEnabled(_ enabled: Bool) {
        unregisterAll()
        guard enabled else { return }
        installHandler()
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for (index, binding) in Self.bindings.enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x4155_5241), id: UInt32(index)) // 'AURA'
            if RegisterEventHotKey(binding.keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let index = Int(hotKeyID.id)
            MainActor.assumeIsolated {
                guard HotKeys.bindings.indices.contains(index) else { return }
                HotKeys.shared.onAction?(HotKeys.bindings[index].action)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
