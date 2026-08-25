# Foliage

## Project Shape

- Run project commands from this directory; `Foliage.xcodeproj` and the `Foliage` scheme are here.
- This is one SwiftUI application target with no test target, package dependencies, lint config, or formatter config.
- `Foliage/FoliageApp.swift` is the app entrypoint and owns the persistent SwiftData `ModelContainer`; register every new `@Model` type in its `Schema`.
- `Foliage/ContentView.swift` owns library/import navigation; `ReaderWorkspace.swift` owns reader controls and notes; `PDFReaderView.swift` is the PDFKit bridge; `DocumentStorage.swift` copies imports into Application Support.
- The target uses an Xcode file-system-synchronized group. New files under `Foliage/` are discovered automatically; do not add ordinary source files to `project.pbxproj` manually.

## Build And Verify

- List the authoritative targets and schemes with `xcodebuild -list -project Foliage.xcodeproj`.
- Verify source changes on macOS without requiring the configured developer team: `xcodebuild -project Foliage.xcodeproj -scheme Foliage -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`.
- Catch iOS-only compile errors with `xcodebuild -project Foliage.xcodeproj -scheme Foliage -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.
- There is currently no automated test command. Do not report tests as passing; use a clean build plus relevant SwiftUI previews/manual platform checks.
- The target supports iPhone, iPad, macOS, and visionOS with deployment target 26.4. Keep shared code compiling across those platforms and guard platform-only APIs explicitly.

## Current Constraints

- Swift concurrency defaults to `MainActor` with approachable concurrency enabled; account for that before adding detached/background work.
- SwiftData is currently local persistent storage. The entitlements request CloudKit but define no iCloud container, so do not assume sync works.
- Imported files are copied into Application Support; never persist a picker URL or assume its security-scoped access survives the import callback.
- The original user-selected files remain read-only. Source editing/export needs an intentional write-back design rather than direct writes.
- PDF highlights, underlines, side notes, bookmarks, and last-page state live in SwiftData. `PDFReaderView` reconstructs visible PDFKit annotations; do not write them into the imported PDF copy.
- PDF selection actions are positioned from PDFKit view coordinates. Preserve the macOS flipped-coordinate check and edge clamping when changing the reader overlay.
- Side notes, free notes, and summaries share `MarkdownEditor.swift`; keep their Markdown editing/preview behavior consistent.
- PDF page indices are stored zero-based and converted to one-based numbers only for display.
- Push notification entitlements and `remote-notification` background mode exist, but there is no registration or handling code yet.
- PDF rendering and annotation are implemented only for iOS and macOS; EPUB import works, but chapter rendering is intentionally postponed.
