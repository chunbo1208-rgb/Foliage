import SwiftUI

enum AppSettingKeys {
    static let appearance = "settings.appearance"
    static let showLaunchScreen = "settings.show-launch-screen"
    static let openContentsSidebar = "settings.open-contents-sidebar"
    static let openNotesSidebar = "settings.open-notes-sidebar"
    static let collapseContents = "settings.collapse-contents"
    static let restoreReadingPosition = "settings.restore-reading-position"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppSettingKeys.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettingKeys.showLaunchScreen) private var showLaunchScreen = true
    @AppStorage(AppSettingKeys.openContentsSidebar) private var openContentsSidebar = true
    @AppStorage(AppSettingKeys.openNotesSidebar) private var openNotesSidebar = false
    @AppStorage(AppSettingKeys.collapseContents) private var collapseContents = true
    @AppStorage(AppSettingKeys.restoreReadingPosition) private var restoreReadingPosition = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                    Text("Customize Foliage across this Mac.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            TabView {
                generalSettings
                    .tabItem { Label("General", systemImage: "gearshape") }
                appearanceSettings
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
                readingSettings
                    .tabItem { Label("Reading", systemImage: "book.pages") }
                KeyboardShortcutsView(showsHeader: false)
                    .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            }
            .padding(12)
        }
#if os(macOS)
        .frame(minWidth: 680, idealWidth: 760, minHeight: 620, idealHeight: 700)
#else
        .frame(minHeight: 560)
#endif
    }

    private var generalSettings: some View {
        Form {
            Section("Startup") {
                Toggle("Show the Foliage launch screen", isOn: $showLaunchScreen)
                Text("The launch screen appears briefly when the app starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceSettings: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text("System follows your Mac’s current light or dark appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var readingSettings: some View {
        Form {
            Section("When Opening a PDF") {
                Toggle("Show Contents and Previews", isOn: $openContentsSidebar)
                Toggle("Show Side Notes", isOn: $openNotesSidebar)
                Toggle("Restore last reading position", isOn: $restoreReadingPosition)
            }

            Section("Table of Contents") {
                Toggle("Start parent sections collapsed", isOn: $collapseContents)
                Text("You can still expand individual sections or use Expand All from the contents menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
