//
//  FoliageApp.swift
//  Foliage
//
//  Created by Chunbo Liu on 8/23/26.
//

import SwiftUI
import SwiftData

@main
struct FoliageApp: App {
    private let persistence = PersistenceSetup.make()
    @State private var shortcutSettings = KeyboardShortcutSettings()

    var body: some Scene {
        WindowGroup {
            FoliageRootView(storageWarning: persistence.warning)
                .environment(shortcutSettings)
        }
        .modelContainer(persistence.container)
        .commands {
            FoliageCommands(settings: shortcutSettings)
        }

#if os(macOS)
        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            KeyboardShortcutsView()
                .environment(shortcutSettings)
        }
        .defaultSize(width: 700, height: 680)
#endif
    }
}

private struct FoliageRootView: View {
    @State private var isShowingLaunch = true
    @AppStorage(AppSettingKeys.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppSettingKeys.showLaunchScreen) private var showLaunchScreen = true

    let storageWarning: String?

    var body: some View {
        ZStack {
            ContentView(storageWarning: storageWarning)

            if isShowingLaunch && showLaunchScreen {
                FoliageLaunchView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                isShowingLaunch = false
            }
        }
    }
}

private struct PersistenceSetup {
    let container: ModelContainer
    let warning: String?

    static func make() -> PersistenceSetup {
        let schema = Schema([
            LibraryDocument.self,
            MarginNote.self,
            ReaderAnnotation.self,
            PageBookmark.self,
            LibraryTag.self,
            LibraryCollection.self,
        ])
        if CloudConfiguration.isEnabled {
            let cloudConfiguration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(CloudConfiguration.containerIdentifier)
            )
            do {
                return PersistenceSetup(
                    container: try ModelContainer(for: schema, configurations: [cloudConfiguration]),
                    warning: nil
                )
            } catch {
                return makeLocal(schema: schema, warning: "iCloud storage could not start. Foliage is using the local library for this session. \(error.localizedDescription)")
            }
        }

        return makeLocal(schema: schema, warning: nil)
    }

    private static func makeLocal(schema: Schema, warning: String?) -> PersistenceSetup {
        let localConfiguration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
        do {
            return PersistenceSetup(
                container: try ModelContainer(for: schema, configurations: [localConfiguration]),
                warning: warning
            )
        } catch let localError {
            let memoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return PersistenceSetup(
                    container: try ModelContainer(for: schema, configurations: [memoryConfiguration]),
                    warning: "Persistent storage could not start. Changes made in this session will not be saved. \(localError.localizedDescription)"
                )
            } catch {
                preconditionFailure("Foliage could not create even a temporary data store: \(error)")
            }
        }
    }
}
