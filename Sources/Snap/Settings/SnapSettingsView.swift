import AppKit
import SwiftUI
import VellforgeKit

/// Snap's Settings pane: dragging behaviour, the gap, and every shortcut.
struct SnapSettingsView: View {

    @AppStorage("vellsnap.dragSnap") private var dragSnap = true
    @AppStorage("vellsnap.layoutBar") private var layoutBar = true
    @AppStorage("vellsnap.gap") private var gap = 0.0

    @State private var message = ""
    /// Bumped to rebuild the recorders after a reset.
    @State private var generation = 0

    var body: some View {
        Section("Dragging") {
            Toggle(isOn: $dragSnap) {
                Text("Snap when dragging to a screen edge")
                Text("Hold ⌃ while dropping for a third, ⌃⇧ for two-thirds.")
            }
            .onChange(of: dragSnap) { _, on in DragSnapController.isEnabled = on }

            Toggle(isOn: $layoutBar) {
                Text("Show the layout chooser at the top of the screen")
                Text("Drag a window toward the top, then drop it into any cell.")
            }

            LabeledContent("Gap between windows") {
                HStack {
                    Slider(value: $gap, in: 0...24, step: 2)
                        .frame(width: 160)
                    Text("\(Int(gap)) pt")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }

        ForEach(Command.groups, id: \.self) { group in
            Section(group) {
                ForEach(Command.allCases.filter { $0.group == group }, id: \.self) { command in
                    // Centred rather than LabeledContent: that aligns by text
                    // baseline, and the AppKit recorder has none, so it sank
                    // below its label.
                    HStack {
                        Text(command.title)
                        Spacer()
                        ShortcutField(command: command, message: $message)
                            .frame(width: 150, height: 24)
                            .id("\(command.rawValue)-\(generation)")
                    }
                }
            }
        }

        Section {
            if !conflictText.isEmpty {
                Text(conflictText).foregroundStyle(.orange).font(.callout)
            }
            if !message.isEmpty {
                Text(message).foregroundStyle(.orange).font(.callout)
            }
            HStack {
                Text("Click a shortcut to change it. Delete clears it, Escape cancels.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Shortcuts") {
                    BindingStore.shared.resetToDefaults()
                    message = ""
                    generation += 1
                }
            }
        }
    }

    /// Shortcuts the system refused because another app owns them.
    private var conflictText: String {
        _ = generation
        let blocked = BindingStore.shared.conflicted
        guard !blocked.isEmpty else { return "" }
        let names = blocked.map(\.title).sorted().joined(separator: ", ")
        return "Already taken by another app, so these don't work: \(names)."
    }
}

/// Hosts Vellsnap's click-to-record field.
private struct ShortcutField: NSViewRepresentable {

    let command: Command
    @Binding var message: String

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let recorder = ShortcutRecorderView()
        recorder.binding = BindingStore.shared.bindings[command]

        // Refuse a combination another command already owns, rather than
        // silently stealing it and leaving the other one dead.
        recorder.validate = { candidate in
            guard let existing = BindingStore.shared.command(using: candidate,
                                                             excluding: command)
            else { return true }
            message = "\(candidate.displayString) is already used by “\(existing.title)”."
            return false
        }
        recorder.onChange = { binding in
            BindingStore.shared.set(binding, for: command)
            message = ""
        }
        return recorder
    }

    func updateNSView(_ recorder: ShortcutRecorderView, context: Context) {}
}
