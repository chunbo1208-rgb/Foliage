# Foliage

Foliage is a SwiftUI reading and note-taking app for iPhone, iPad, and macOS. It keeps documents, reading progress, highlights, bookmarks, side notes, free notes, and summaries together in a personal library.

## Current Features

- Two-column Books-style library with typo-tolerant search across metadata and notes, sorting, reading statuses, tags, collections, PDF covers, and progress.
- Import for PDF, Markdown, text, LaTeX, and EPUB files, copied into app storage for persistent access.
- Native PDF reading with page restoration, table of contents, page jump, and bookmarks.
- Persistent PDF highlights, underlines, and passage-linked side notes with an eight-color palette.
- Page-aware free notes and a separate book summary editor.
- Collapsible long notes and expanded note editing.
- Automatic Markdown preview and offline inline/display math rendering.
- Adaptive cover grid on large screens and a compact library/reader layout on iPhone.
- Recoverable missing-file state with document replacement.
- CloudKit-compatible library information and reading notes, with cloud availability in the sidebar.
- Tag filters in the library sidebar; tags with the same name are shown as one logical filter.
- Persistent author metadata and selectable PDF-first-page, custom-image, or typographic theme covers.
- Reader controls to return to the library and independently collapse the library and side-note bars.

EPUB files can currently be imported but not read. Imported source files remain local; synced library entries offer **Locate File** when their source file is unavailable on the current device.

## Sync Behavior After Activation

- Side notes, highlights, underlines, bookmarks, and free notes are independent records. Additions made on different devices are preserved together.
- Tags and collection links added independently are merged through their relationships.
- Concurrent edits to different records merge normally.
- Concurrent edits to the exact same text or scalar field use CloudKit's last-writer-wins behavior.
- Sync is asynchronous and continues after local saves; the sidebar reports account availability, not a false "fully synced" state.

## Next Steps

Complete these milestones in order and keep macOS and iOS builds working after each one.

### 1. Stabilize and Test the Current App

- [x] Replace the startup `fatalError` with a recoverable storage error or safe local fallback.
- [x] Remove the redundant middle library column and show covers in the main window.
- [x] Replace conflicting system/custom sidebar selections with one green selection state.
- [x] Flatten the sort menu, show the active sort icon, and compact the sort/import controls.
- [x] Replace duplicate import actions with the toolbar `+` button.
- [x] Search titles, file names, formats, statuses, tags, summaries, notes, and selected passages with typo tolerance.
- [x] Widen and align the library sidebar so icons and full labels remain readable.
- [x] Add author editing and selectable PDF, custom-image, and theme cover sources.
- [x] Replace the default metadata form with a grouped details sheet and selectable tag/collection tiles.
- [x] Exit side-note editing when the user clicks outside the active editor on macOS.
- [x] Add reader actions for Back to Library and independent left/right sidebar visibility.
- [ ] Audit library navigation, importing multiple files, rename, delete, tags, collections, status changes, sorting, and missing-file recovery.
- [ ] Audit PDF selection, annotation positioning, recoloring, deletion, bookmarks, page restoration, and note persistence on macOS and iOS.
- [ ] Check note editing, Markdown/math rendering, keyboard behavior, dark mode, Dynamic Type, and VoiceOver.
- [ ] Add a test target for filtering, sorting, model relationships, note persistence, and future migrations.

Done when both platform builds pass and the core library/PDF workflow has no known data-loss or crash paths.

### 2. Prepare the Data Model for Sync

- [x] Use metadata-and-notes sync first; keep imported source files local.
- [ ] Define a versioned SwiftData schema and migration plan for existing local libraries.
- [x] Remove unsupported uniqueness constraints and make defaults and relationships CloudKit-compatible.
- [x] Define additive record merging and last-writer-wins scalar conflict behavior.
- [ ] Test migration from the current schema with a populated local library.

Recommended first scope: sync metadata, notes, annotations, bookmarks, summaries, tags, collections, and reading progress. Keep source files local and offer **Locate File** on devices where the document is unavailable.

### 3. Add CloudKit Sync

- [x] Prepare the project for `iCloud.com.chunboblog.Foliage`.
- [ ] Move the app from the current Personal Team to a paid Apple Developer team, then attach `Foliage.entitlements` to each build configuration.
- [ ] Set `CloudConfiguration.isEnabled` to `true` after the CloudKit entitlement signs successfully.
- [x] Configure the SwiftData `ModelContainer` for CloudKit with a safe local fallback.
- [x] Add non-blocking account and source-file availability indicators.
- [ ] Handle disabled iCloud, account changes, offline edits, storage limits, and sync failures without blocking local reading.
- [ ] Test create, edit, conflict, reconnect, and delete flows on two physical devices.

Done when existing local data migrates safely and reading data converges across two devices without losing offline changes.

### 4. Add EPUB Reading

- [ ] Parse EPUB metadata, cover, spine, chapters, and table of contents.
- [ ] Render chapters with accessible typography and navigation.
- [ ] Persist EPUB reading position and progress.
- [ ] Support text selection, highlights, and side-note anchors with stable EPUB locations.
- [ ] Restore annotations after relaunch and layout/font-size changes.

### 5. Add Export and Source Editing

- [ ] Export notes and summaries to Markdown with links to PDF pages or EPUB locations.
- [ ] Define an explicit save/export workflow for editable Markdown and LaTeX documents.
- [ ] Keep imported source documents read-only until conflict handling and write-back behavior are designed.
- [ ] Consider full-text search across documents and notes after export is stable.

## Later Ideas

- [ ] Render inactive Markdown lines while keeping only the focused line editable.
- [ ] Add web search and system lookup actions to selected text.
- [ ] Add optional page-turning modes alongside continuous PDF scrolling.
- [ ] Consider syncing imported files through CloudKit assets or iCloud Drive.

## Run in Xcode

1. Open `Foliage.xcodeproj` in Xcode.
2. Select the `Foliage` scheme.
3. Choose My Mac, an iPhone/iPad simulator, or a connected device.
4. Press **Command-R** and import a supported document.

## Build Checks

Run from this directory:

```sh
xcodebuild -project Foliage.xcodeproj -scheme Foliage -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Foliage.xcodeproj -scheme Foliage -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

There is currently no automated test target. Until one is added, use both builds plus manual checks on macOS and at least one iPhone or iPad size.

## Release Order

1. Stability, manual verification, and automated test foundation.
2. Versioned data model and migration coverage.
3. CloudKit metadata and note sync.
4. EPUB reading and annotations.
5. Note export and editable text-source workflows.
