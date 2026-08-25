import Observation
import SwiftUI

enum FoliageShortcutAction: String, CaseIterable, Codable, Identifiable {
    case importDocument
    case showLibrary
    case toggleLibrarySidebar
    case previousPage
    case nextPage
    case firstPage
    case lastPage
    case jumpToPage
    case toggleNavigation
    case toggleBookmark
    case editInformation
    case editContents
    case showSummary
    case showNotes

    var id: Self { self }

    var title: String {
        switch self {
        case .importDocument: "Import Document"
        case .showLibrary: "Back to Library"
        case .toggleLibrarySidebar: "Toggle Library Sidebar"
        case .previousPage: "Previous Page"
        case .nextPage: "Next Page"
        case .firstPage: "First Page"
        case .lastPage: "Last Page"
        case .jumpToPage: "Jump to Page"
        case .toggleNavigation: "Toggle Contents and Previews"
        case .toggleBookmark: "Toggle Page Bookmark"
        case .editInformation: "Edit PDF Information"
        case .editContents: "Edit Contents"
        case .showSummary: "Show Book Summary"
        case .showNotes: "Show Notes"
        }
    }

    var section: String {
        switch self {
        case .importDocument, .showLibrary, .toggleLibrarySidebar: "Library"
        case .previousPage, .nextPage, .firstPage, .lastPage, .jumpToPage: "Navigation"
        case .toggleNavigation, .toggleBookmark, .editInformation, .editContents, .showSummary, .showNotes:
            "Reader"
        }
    }
}

enum FoliageShortcutKey: String, CaseIterable, Codable, Identifiable {
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z
    case zero = "0", one = "1", two = "2", three = "3", four = "4"
    case five = "5", six = "6", seven = "7", eight = "8", nine = "9"
    case leftBracket = "["
    case rightBracket = "]"
    case slash = "/"
    case comma = ","
    case period = "."
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case home
    case end

    var id: Self { self }

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .leftArrow: .leftArrow
        case .rightArrow: .rightArrow
        case .upArrow: .upArrow
        case .downArrow: .downArrow
        case .home: .home
        case .end: .end
        default: KeyEquivalent(Character(rawValue))
        }
    }

    var displayName: String {
        switch self {
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .home: "Home"
        case .end: "End"
        default: rawValue.uppercased()
        }
    }
}

enum FoliageShortcutModifier: String, CaseIterable, Codable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: Self { self }

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }

    var eventModifier: EventModifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }
}

struct FoliageShortcutAssignment: Codable, Equatable {
    var key: FoliageShortcutKey
    var modifiers: Set<FoliageShortcutModifier>

    var eventModifiers: EventModifiers {
        modifiers.reduce(into: EventModifiers()) { result, modifier in
            result.insert(modifier.eventModifier)
        }
    }

    var displayName: String {
        let modifierText = FoliageShortcutModifier.allCases
            .filter(modifiers.contains)
            .map(\.symbol)
            .joined()
        return modifierText + key.displayName
    }
}

@Observable
final class KeyboardShortcutSettings {
    private static let storageKey = "foliage.keyboard-shortcuts"

    var assignments: [FoliageShortcutAction: FoliageShortcutAssignment] {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(
               [FoliageShortcutAction: FoliageShortcutAssignment].self,
               from: data
           ) {
            assignments = Self.defaults.merging(saved) { _, saved in saved }
        } else {
            assignments = Self.defaults
        }
    }

    subscript(action: FoliageShortcutAction) -> FoliageShortcutAssignment {
        get { assignments[action] ?? Self.defaults[action]! }
        set { assignments[action] = newValue }
    }

    func reset() {
        assignments = Self.defaults
    }

    func hasConflict(for action: FoliageShortcutAction) -> Bool {
        let assignment = self[action]
        return assignments.contains { otherAction, otherAssignment in
            otherAction != action && otherAssignment == assignment
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(assignments) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static let defaults: [FoliageShortcutAction: FoliageShortcutAssignment] = [
        .importDocument: .init(key: .o, modifiers: [.command]),
        .showLibrary: .init(key: .l, modifiers: [.command, .shift]),
        .toggleLibrarySidebar: .init(key: .l, modifiers: [.command, .control]),
        .previousPage: .init(key: .leftBracket, modifiers: [.command]),
        .nextPage: .init(key: .rightBracket, modifiers: [.command]),
        .firstPage: .init(key: .upArrow, modifiers: [.command]),
        .lastPage: .init(key: .downArrow, modifiers: [.command]),
        .jumpToPage: .init(key: .j, modifiers: [.command]),
        .toggleNavigation: .init(key: .t, modifiers: [.command, .shift]),
        .toggleBookmark: .init(key: .b, modifiers: [.command]),
        .editInformation: .init(key: .i, modifiers: [.command, .shift]),
        .editContents: .init(key: .c, modifiers: [.command, .shift]),
        .showSummary: .init(key: .s, modifiers: [.command, .shift]),
        .showNotes: .init(key: .n, modifiers: [.command, .shift]),
    ]
}

struct LibraryCommandActions {
    let importDocument: () -> Void
    let showLibrary: () -> Void
    let toggleLibrarySidebar: () -> Void
    let showSettings: () -> Void
}

struct ReaderCommandActions {
    let previousPage: () -> Void
    let nextPage: () -> Void
    let firstPage: () -> Void
    let lastPage: () -> Void
    let jumpToPage: () -> Void
    let toggleNavigation: () -> Void
    let toggleBookmark: () -> Void
    let editInformation: () -> Void
    let editContents: () -> Void
    let showSummary: () -> Void
    let showNotes: () -> Void
}

private struct LibraryCommandActionsKey: FocusedValueKey {
    typealias Value = LibraryCommandActions
}

private struct ReaderCommandActionsKey: FocusedValueKey {
    typealias Value = ReaderCommandActions
}

extension FocusedValues {
    var libraryCommandActions: LibraryCommandActions? {
        get { self[LibraryCommandActionsKey.self] }
        set { self[LibraryCommandActionsKey.self] = newValue }
    }

    var readerCommandActions: ReaderCommandActions? {
        get { self[ReaderCommandActionsKey.self] }
        set { self[ReaderCommandActionsKey.self] = newValue }
    }
}

struct FoliageCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.libraryCommandActions) private var libraryActions
    @FocusedValue(\.readerCommandActions) private var readerActions

    let settings: KeyboardShortcutSettings

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Settings…") {
                libraryActions?.showSettings()
            }
            .keyboardShortcut(",", modifiers: [.command])
            .disabled(libraryActions == nil)
        }

        CommandGroup(after: .newItem) {
            command("Import Document…", action: .importDocument) {
                libraryActions?.importDocument()
            }
            .disabled(libraryActions == nil)
        }

        CommandMenu("Navigate") {
            command("Back to Library", action: .showLibrary) { libraryActions?.showLibrary() }
            command("Toggle Library Sidebar", action: .toggleLibrarySidebar) {
                libraryActions?.toggleLibrarySidebar()
            }
            Divider()
            command("Previous Page", action: .previousPage) { readerActions?.previousPage() }
            command("Next Page", action: .nextPage) { readerActions?.nextPage() }
            command("First Page", action: .firstPage) { readerActions?.firstPage() }
            command("Last Page", action: .lastPage) { readerActions?.lastPage() }
            command("Jump to Page…", action: .jumpToPage) { readerActions?.jumpToPage() }
                .disabled(readerActions == nil)
        }

        CommandMenu("Reader") {
            command("Toggle Contents and Previews", action: .toggleNavigation) {
                readerActions?.toggleNavigation()
            }
            command("Toggle Page Bookmark", action: .toggleBookmark) {
                readerActions?.toggleBookmark()
            }
            Divider()
            command("Edit PDF Information…", action: .editInformation) {
                readerActions?.editInformation()
            }
            command("Edit Contents…", action: .editContents) { readerActions?.editContents() }
            command("Book Summary…", action: .showSummary) { readerActions?.showSummary() }
            command("Notes…", action: .showNotes) { readerActions?.showNotes() }
#if os(macOS)
            Divider()
            Button("Keyboard Shortcuts…") {
                openWindow(id: "keyboard-shortcuts")
            }
            .keyboardShortcut("/", modifiers: [.command])
#endif
        }
    }

    private func command(
        _ title: String,
        action: FoliageShortcutAction,
        perform: @escaping () -> Void
    ) -> some View {
        let shortcut = settings[action]
        return Button(title, action: perform)
            .keyboardShortcut(shortcut.key.keyEquivalent, modifiers: shortcut.eventModifiers)
            .disabled(action.section != "Library" && readerActions == nil)
    }
}

struct KeyboardShortcutsView: View {
    @Environment(KeyboardShortcutSettings.self) private var settings
    var showsHeader = true

    var body: some View {
        @Bindable var settings = settings

        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keyboard Shortcuts")
                            .font(.title2.weight(.semibold))
                        Text("Choose a key and any modifier combination. Changes apply immediately.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restore Defaults") { settings.reset() }
                }
                .padding(24)

                Divider()
            }

            List {
                if !showsHeader {
                    Section {
                        HStack {
                            Text("Changes apply immediately.")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore Defaults") { settings.reset() }
                        }
                    }
                }
                ForEach(["Library", "Navigation", "Reader"], id: \.self) { section in
                    Section(section) {
                        ForEach(FoliageShortcutAction.allCases.filter { $0.section == section }) { action in
                            ShortcutEditorRow(
                                action: action,
                                assignment: Binding(
                                    get: { settings[action] },
                                    set: { settings[action] = $0 }
                                ),
                                hasConflict: settings.hasConflict(for: action)
                            )
                        }
                    }
                }
            }
        }
        .frame(minWidth: 620, idealWidth: 700, minHeight: 600)
    }
}

private struct ShortcutEditorRow: View {
    let action: FoliageShortcutAction
    @Binding var assignment: FoliageShortcutAssignment
    let hasConflict: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(action.title)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(FoliageShortcutModifier.allCases) { modifier in
                    Button(modifier.symbol) { toggle(modifier) }
                        .buttonStyle(.bordered)
                        .tint(assignment.modifiers.contains(modifier) ? .foliageGreen : .secondary)
                        .accessibilityLabel(modifier.rawValue.capitalized)
                }

                Picker("Key", selection: $assignment.key) {
                    ForEach(FoliageShortcutKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .labelsHidden()
                .frame(width: 82)
            }

            Text(assignment.displayName)
                .font(.system(.body, design: .monospaced))
                .frame(width: 72, alignment: .trailing)
                .foregroundStyle(hasConflict ? .red : .secondary)
        }
        .padding(.vertical, 3)
        .help(hasConflict ? "This shortcut is assigned to more than one action." : action.title)
    }

    private func toggle(_ modifier: FoliageShortcutModifier) {
        if assignment.modifiers.contains(modifier) {
            assignment.modifiers.remove(modifier)
        } else {
            assignment.modifiers.insert(modifier)
        }
    }
}
