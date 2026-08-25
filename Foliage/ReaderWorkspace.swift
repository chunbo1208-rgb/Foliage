import SwiftData
import SwiftUI

struct ReaderWorkspace: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Bindable var document: LibraryDocument
    let libraryAction: () -> Void

    @AppStorage(AppSettingKeys.openContentsSidebar) private var openContentsSidebar = true
    @AppStorage(AppSettingKeys.openNotesSidebar) private var openNotesSidebar = false

    @State private var isLocatingFile = false
    @State private var isNavigationVisible = true
    @State private var isNotesVisible = false
    @State private var hasAppliedSidebarDefaults = false
    @State private var fileRevision = 0
    @State private var recoveryError: String?

    var body: some View {
        Group {
            if !documentFileExists {
                MissingDocumentView(
                    fileName: document.originalFileName,
                    locateAction: { isLocatingFile = true }
                )
            } else if document.fileExtension == "pdf" {
#if canImport(PDFKit) && (os(macOS) || os(iOS))
                PDFReadingWorkspace(
                    document: document,
                    isNavigationVisible: $isNavigationVisible,
                    isNotesVisible: $isNotesVisible
                )
#else
                ContentUnavailableView(
                    "PDF preview unavailable",
                    systemImage: "doc.richtext",
                    description: Text("PDF rendering is not available on this platform yet.")
                )
#endif
            } else if horizontalSizeClass == .compact {
                TabView {
                    GenericReaderPane(document: document)
                        .tabItem { Label("Document", systemImage: "book.pages") }
                    NotesPane(document: document, pageIndex: nil)
                        .tabItem { Label("Notes", systemImage: "note.text") }
                }
            } else {
                HStack(spacing: 0) {
                    GenericReaderPane(document: document)
                    if isNotesVisible {
                        Divider()
                        NotesPane(document: document, pageIndex: nil)
                            .frame(minWidth: 290, idealWidth: 340, maxWidth: 420)
                    }
                }
            }
        }
        .id(fileRevision)
        .navigationTitle(document.title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: libraryAction) {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Back to Library")
                .accessibilityLabel("Back to Library")

                if document.fileExtension == "pdf" {
                    Button { isNavigationVisible.toggle() } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help(isNavigationVisible ? "Hide contents and previews" : "Show contents and previews")
                    .accessibilityLabel(isNavigationVisible ? "Hide contents and previews" : "Show contents and previews")
                }

                Button { isNotesVisible.toggle() } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(isNotesVisible ? "Hide side notes" : "Show side notes")
                .accessibilityLabel(isNotesVisible ? "Hide side notes" : "Show side notes")
            }
        }
#if os(macOS)
        .toolbar(removing: .sidebarToggle)
#endif
        .onAppear {
            if !hasAppliedSidebarDefaults {
                isNavigationVisible = openContentsSidebar
                isNotesVisible = openNotesSidebar
                hasAppliedSidebarDefaults = true
            }
            document.lastOpenedAt = Date()
            document.hasBeenOpened = true
            if document.readingStatus == .wantToRead {
                document.readingStatus = .reading
            }
        }
        .fileImporter(
            isPresented: $isLocatingFile,
            allowedContentTypes: DocumentStorage.importableTypes,
            allowsMultipleSelection: false,
            onCompletion: replaceMissingFile
        )
        .alert("Couldn’t restore document", isPresented: Binding(
            get: { recoveryError != nil },
            set: { if !$0 { recoveryError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryError ?? "Unknown error")
        }
    }

    private var documentFileExists: Bool {
        guard let url = try? DocumentStorage.fileURL(for: document) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func replaceMissingFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            try DocumentStorage.replaceFile(for: document, with: url)
            fileRevision += 1
        } catch {
            recoveryError = error.localizedDescription
        }
    }
}

private struct MissingDocumentView: View {
    let fileName: String
    let locateAction: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Document file missing", systemImage: "doc.badge.ellipsis")
        } description: {
            Text("Foliage still has your notes and reading progress, but \(fileName) is no longer in app storage.")
        } actions: {
            Button("Locate File", action: locateAction)
                .buttonStyle(.borderedProminent)
        }
    }
}

#if canImport(PDFKit) && (os(macOS) || os(iOS))
private struct PDFReadingWorkspace: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: LibraryDocument
    @Binding var isNavigationVisible: Bool
    @Binding var isNotesVisible: Bool

    @State private var currentPage: Int
    @State private var pageCount: Int
    @State private var selection: PDFSelectionSnapshot?
    @State private var annotationTap: PDFAnnotationTap?
    @State private var outlineItems: [PDFOutlineItem]
    @State private var isShowingBookmarks = false
    @State private var isShowingSearch = false
    @State private var isShowingJump = false
    @State private var isShowingSummary = false
    @State private var isShowingInformation = false
    @State private var isEditingContents = false
    @State private var isShowingSideNote = false
    @State private var jumpText = ""
    @State private var noteDraft = ""
    @State private var selectedColorHex = AnnotationPalette.defaultHex

    private let fileURL: URL?

    init(
        document: LibraryDocument,
        isNavigationVisible: Binding<Bool>,
        isNotesVisible: Binding<Bool>
    ) {
        self.document = document
        _isNavigationVisible = isNavigationVisible
        _isNotesVisible = isNotesVisible
        let url = try? DocumentStorage.fileURL(for: document)
        self.fileURL = url
        let restoreReadingPosition = UserDefaults.standard.object(
            forKey: AppSettingKeys.restoreReadingPosition
        ) as? Bool ?? true
        _currentPage = State(initialValue: restoreReadingPosition ? max(0, document.lastPageIndex) : 0)
        _pageCount = State(initialValue: 0)
        _outlineItems = State(initialValue: [])
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                TabView {
                    pdfPane
                        .tabItem { Label("Document", systemImage: "book.pages") }
                    PDFNavigationSidebar(
                        url: fileURL,
                        items: $outlineItems,
                        currentPage: currentPage,
                        pageCount: pageCount,
                        isEditing: $isEditingContents,
                        jumpAction: jump,
                        informationAction: { isShowingInformation = true }
                    )
                    .tabItem { Label("Contents", systemImage: "list.bullet") }
                    NotesPane(
                        document: document,
                        pageIndex: currentPage,
                        selectedAnnotationID: annotationTap?.annotationID
                    )
                        .tabItem { Label("Notes", systemImage: "note.text") }
                }
            } else {
                HStack(spacing: 0) {
                    if isNavigationVisible {
                        PDFNavigationSidebar(
                            url: fileURL,
                            items: $outlineItems,
                            currentPage: currentPage,
                            pageCount: pageCount,
                            isEditing: $isEditingContents,
                            jumpAction: jump,
                            informationAction: { isShowingInformation = true }
                        )
                        .frame(minWidth: 250, idealWidth: 290, maxWidth: 360)
                        Divider()
                    }

                    pdfPane

                    if isNotesVisible {
                        Divider()
                        NotesPane(
                            document: document,
                            pageIndex: currentPage,
                            selectedAnnotationID: annotationTap?.annotationID
                        )
                        .frame(minWidth: 300, idealWidth: 350, maxWidth: 440)
                    }
                }
            }
        }
        .onChange(of: currentPage) {
            document.lastPageIndex = currentPage
            updateReadingProgress()
        }
        .onChange(of: pageCount, updateReadingProgress)
        .task(id: fileURL) {
            guard let fileURL else { return }
            let metadata = PDFOutlineLoader.load(from: fileURL)
            outlineItems = decodedContents ?? metadata.items
            pageCount = metadata.pageCount
            updateReadingProgress()
        }
        .onChange(of: outlineItems) {
            guard let data = try? JSONEncoder().encode(outlineItems),
                  let json = String(data: data, encoding: .utf8) else { return }
            document.pdfContentsJSON = json
        }
        .sheet(isPresented: $isShowingSummary) {
            SummaryEditor(document: document)
        }
        .sheet(isPresented: $isShowingInformation) {
            PDFInformationEditor(document: document)
        }
        .sheet(isPresented: $isShowingSideNote) {
            SideNoteComposer(
                quote: selection?.text ?? "",
                note: $noteDraft,
                cancelAction: { isShowingSideNote = false },
                saveAction: saveSideNote
            )
        }
        .focusedSceneValue(\.readerCommandActions, ReaderCommandActions(
            previousPage: { jump(to: currentPage - 1) },
            nextPage: { jump(to: currentPage + 1) },
            firstPage: { jump(to: 0) },
            lastPage: { jump(to: pageCount - 1) },
            jumpToPage: showPageJump,
            toggleNavigation: { isNavigationVisible.toggle() },
            toggleBookmark: toggleBookmark,
            editInformation: { isShowingInformation = true },
            editContents: showContentsEditor,
            showSummary: { isShowingSummary = true },
            showNotes: { isNotesVisible = true }
        ))
    }

    private var pdfPane: some View {
        VStack(spacing: 0) {
            pdfToolbar
            ZStack(alignment: .bottom) {
                if let fileURL {
                    PDFContainer(
                        url: fileURL,
                        annotations: document.annotations ?? [],
                        currentPage: $currentPage,
                        pageCount: $pageCount,
                        selection: $selection,
                        annotationTap: $annotationTap
                    )
                } else {
                    ContentUnavailableView(
                        "PDF file missing",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The imported file could not be found in app storage.")
                    )
                }

                if let selection {
                    GeometryReader { proxy in
                        SelectionActionBar(
                            selectedColorHex: $selectedColorHex,
                            highlightAction: { addMarkup(.highlight, from: selection) },
                            underlineAction: { addMarkup(.underline, from: selection) },
                            sideNoteAction: {
                                noteDraft = ""
                                isShowingSideNote = true
                            }
                        )
                        .fixedSize()
                        .position(actionPosition(for: selection.actionAnchor, in: proxy.size))
                    }
                }

                if let annotationTap,
                   let annotation = document.annotations?.first(where: { $0.id == annotationTap.annotationID }) {
                    GeometryReader { proxy in
                        ExistingAnnotationActionBar(
                            annotation: annotation,
                            colorAction: { updateColor($0, for: annotation) },
                            deleteAction: { deleteAnnotation(annotation) },
                            closeAction: { self.annotationTap = nil }
                        )
                        .fixedSize()
                        .position(actionPosition(for: annotationTap.actionAnchor, in: proxy.size))
                    }
                }
            }
        }
    }

    private var pdfToolbar: some View {
        HStack(spacing: 12) {
            Text("PDF")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.foliageGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.foliageGreen.opacity(0.1), in: Capsule())

            Text(pageCount == 0 ? "Opening…" : "Page \(currentPage + 1) of \(pageCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: toggleBookmark) {
                Image(systemName: isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
            }
            .help(isCurrentPageBookmarked ? "Remove bookmark" : "Bookmark this page")

            Button { isShowingSearch.toggle() } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Search in PDF")
            .popover(isPresented: $isShowingSearch) {
                PDFSearchPopover(url: fileURL, jumpAction: jump)
            }

            Menu {
                Button("Edit PDF Information…", systemImage: "info.circle") {
                    isShowingInformation = true
                }
                Button("Edit Contents…", systemImage: "list.bullet.indent") {
                    showContentsEditor()
                }
            } label: {
                Label("Edit PDF", systemImage: "pencil")
            }
            .help("Edit PDF information or contents")

            Button { isShowingBookmarks.toggle() } label: {
                Image(systemName: "bookmark.square")
            }
            .help("Bookmarks")
            .popover(isPresented: $isShowingBookmarks) {
                BookmarksPopover(
                    bookmarks: document.bookmarks ?? [],
                    jumpAction: jump,
                    deleteAction: deleteBookmark
                )
            }

            Button {
                showPageJump()
            } label: {
                Image(systemName: "arrow.right.to.line.compact")
            }
            .help("Jump to page")
            .popover(isPresented: $isShowingJump) {
                PageJumpPopover(
                    pageText: $jumpText,
                    pageCount: pageCount,
                    jumpAction: jumpToEnteredPage
                )
            }

            Button { isShowingSummary = true } label: {
                Image(systemName: "text.alignleft")
            }
            .help("Book summary")

            Button { isNotesVisible.toggle() } label: {
                Image(systemName: "note.text")
            }
            .help(isNotesVisible ? "Hide notes" : "Show notes")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var isCurrentPageBookmarked: Bool {
        document.bookmarks?.contains { $0.pageIndex == currentPage } == true
    }

    private var decodedContents: [PDFOutlineItem]? {
        guard !document.pdfContentsJSON.isEmpty,
              let data = document.pdfContentsJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([PDFOutlineItem].self, from: data)
    }

    private func updateReadingProgress() {
        guard pageCount > 0 else { return }
        document.totalPageCount = pageCount
        document.readingProgress = min(1, max(0, Double(currentPage + 1) / Double(pageCount)))
    }

    private func actionPosition(for anchor: CGPoint, in size: CGSize) -> CGPoint {
        let horizontalMargin: CGFloat = 145
        let x = min(max(horizontalMargin, anchor.x), max(horizontalMargin, size.width - horizontalMargin))
        let y = anchor.y > 100
            ? anchor.y - 62
            : anchor.y + 70
        return CGPoint(x: x, y: min(max(32, y), max(32, size.height - 32)))
    }

    private func addMarkup(_ kind: AnnotationKind, from selection: PDFSelectionSnapshot) {
        let annotation = ReaderAnnotation(
            kind: kind,
            selectedText: selection.text,
            colorHex: selectedColorHex,
            pageIndex: selection.pageIndex,
            bounds: selection.bounds
        )
        document.annotations = (document.annotations ?? []) + [annotation]
        modelContext.insert(annotation)
        self.selection = nil
        annotationTap = nil
    }

    private func saveSideNote() {
        guard let selection else { return }
        let annotation = ReaderAnnotation(
            kind: .sideNote,
            selectedText: selection.text,
            noteBody: noteDraft.trimmingCharacters(in: .whitespacesAndNewlines),
            colorHex: selectedColorHex,
            pageIndex: selection.pageIndex,
            bounds: selection.bounds
        )
        document.annotations = (document.annotations ?? []) + [annotation]
        modelContext.insert(annotation)
        self.selection = nil
        annotationTap = nil
        isShowingSideNote = false
    }

    private func updateColor(_ colorHex: String, for annotation: ReaderAnnotation) {
        annotation.colorHex = colorHex
        annotation.updatedAt = Date()
    }

    private func deleteAnnotation(_ annotation: ReaderAnnotation) {
        modelContext.delete(annotation)
        annotationTap = nil
    }

    private func toggleBookmark() {
        if let existing = document.bookmarks?.first(where: { $0.pageIndex == currentPage }) {
            modelContext.delete(existing)
        } else {
            let bookmark = PageBookmark(pageIndex: currentPage, title: "Page \(currentPage + 1)")
            document.bookmarks = (document.bookmarks ?? []) + [bookmark]
            modelContext.insert(bookmark)
        }
    }

    private func deleteBookmark(_ bookmark: PageBookmark) {
        modelContext.delete(bookmark)
    }

    private func jump(to pageIndex: Int) {
        currentPage = min(max(0, pageIndex), max(0, pageCount - 1))
        isShowingBookmarks = false
        isShowingJump = false
    }

    private func showPageJump() {
        jumpText = "\(currentPage + 1)"
        isShowingJump = true
    }

    private func showContentsEditor() {
        isNavigationVisible = true
        isEditingContents = true
    }

    private func jumpToEnteredPage() {
        guard let page = Int(jumpText) else { return }
        jump(to: page - 1)
    }
}

private struct PDFSearchPopover: View {
    let url: URL?
    let jumpAction: (Int) -> Void

    @State private var query = ""
    @State private var results: [PDFSearchResult] = []
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search the whole PDF", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(11)

            Divider()

            Group {
                if isSearching {
                    ProgressView("Searching all pages…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        "Search This PDF",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Enter a word or phrase to search every page.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: trimmedQuery)
                } else {
                    List(results) { result in
                        Button {
                            jumpAction(result.pageIndex)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Page \(result.pageIndex + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.foliageGreen)
                                Text(result.excerpt)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .safeAreaInset(edge: .top) {
                        Text("\(results.count) \(results.count == 1 ? "result" : "results")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.bar)
                    }
                }
            }
        }
        .frame(minWidth: 360, idealWidth: 420, minHeight: 420, idealHeight: 520)
        .onAppear { isSearchFocused = true }
        .task(id: trimmedQuery) {
            guard let url, !trimmedQuery.isEmpty else {
                results = []
                isSearching = false
                return
            }

            isSearching = true
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            let searchQuery = trimmedQuery
            let matches = await Task.detached(priority: .userInitiated) {
                PDFSearchLoader.search(searchQuery, in: url)
            }.value
            guard !Task.isCancelled else { return }
            results = matches
            isSearching = false
        }
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SelectionActionBar: View {
    @Binding var selectedColorHex: String
    let highlightAction: () -> Void
    let underlineAction: () -> Void
    let sideNoteAction: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 18) {
                actionButton("Highlight", systemImage: "highlighter", action: highlightAction)
                actionButton("Underline", systemImage: "underline", action: underlineAction)
                actionButton("Side note", systemImage: "note.text.badge.plus", action: sideNoteAction)
            }
            AnnotationColorRow(selectedColorHex: $selectedColorHex)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 5)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .help(title)
    }
}

private struct ExistingAnnotationActionBar: View {
    let annotation: ReaderAnnotation
    let colorAction: (String) -> Void
    let deleteAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 18) {
                Label(annotation.kind == .underline ? "Underline" : "Highlight", systemImage: annotation.kind == .underline ? "underline" : "highlighter")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                }
                .help("Delete annotation")
                Button(action: closeAction) {
                    Image(systemName: "xmark")
                }
                .help("Close")
            }
            AnnotationColorRow(
                selectedColorHex: Binding(
                    get: { annotation.colorHex },
                    set: colorAction
                )
            )
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 5)
    }
}

private struct AnnotationColorRow: View {
    @Binding var selectedColorHex: String

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AnnotationPalette.colors) { option in
                Button {
                    selectedColorHex = option.hex
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 19, height: 19)
                        .overlay {
                            if selectedColorHex == option.hex {
                                Circle().stroke(.white, lineWidth: 2)
                                Circle().stroke(.black.opacity(0.45), lineWidth: 4)
                                    .padding(-2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(option.name)
            }
        }
    }
}

private struct AnnotationColorOption: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
    var color: Color { Color(annotationHex: hex) }
}

private enum AnnotationPalette {
    static let defaultHex = "FFE052"
    static let colors = [
        AnnotationColorOption(name: "Coral", hex: "FF6B6B"),
        AnnotationColorOption(name: "Orange", hex: "FFB45E"),
        AnnotationColorOption(name: "Yellow", hex: defaultHex),
        AnnotationColorOption(name: "Green", hex: "36E87A"),
        AnnotationColorOption(name: "Cyan", hex: "38DDE3"),
        AnnotationColorOption(name: "Magenta", hex: "E85BD5"),
        AnnotationColorOption(name: "Purple", hex: "B66AC2"),
        AnnotationColorOption(name: "Gray", hex: "BFC2C5"),
    ]
}

private extension Color {
    init(annotationHex hex: String) {
        let value = UInt64(hex, radix: 16) ?? 0xFFE052
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct SideNoteComposer: View {
    let quote: String
    @Binding var note: String
    let cancelAction: () -> Void
    let saveAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Side Note")
                .font(.system(.title2, design: .serif, weight: .semibold))
            Text(quote)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(5)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.foliageGreen).frame(width: 3)
                }
            MarkdownEditor(
                text: $note,
                placeholder: "Write the connection, question, or explanation this passage prompted…",
                minHeight: 150
            )
            HStack {
                Spacer()
                Button("Cancel", action: cancelAction)
                Button("Save Note", action: saveAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 340)
    }
}

private enum PDFNavigationSection: String, CaseIterable, Identifiable {
    case contents
    case previews

    var id: Self { self }

    var title: String {
        switch self {
        case .contents: "Contents"
        case .previews: "Previews"
        }
    }

    var systemImage: String {
        switch self {
        case .contents: "list.bullet"
        case .previews: "rectangle.grid.1x2"
        }
    }
}

private struct PDFNavigationSidebar: View {
    @AppStorage(AppSettingKeys.collapseContents) private var collapseContents = true

    let url: URL?
    @Binding var items: [PDFOutlineItem]
    let currentPage: Int
    let pageCount: Int
    @Binding var isEditing: Bool
    let jumpAction: (Int) -> Void
    let informationAction: () -> Void

    @State private var section = PDFNavigationSection.contents
    @State private var collapsedItemIDs: Set<UUID> = []
    @State private var hasInitializedCollapsedItems = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Navigation", selection: $section) {
                    ForEach(PDFNavigationSection.allCases) { item in
                        Label(item.title, systemImage: item.systemImage)
                            .labelStyle(.iconOnly)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .help(section.title)

                Spacer()

                if section == .contents {
                    Button(isEditing ? "Done" : "Edit") {
                        isEditing.toggle()
                    }
                    .buttonStyle(.borderless)
                }

                Menu {
                    Button("Edit PDF Information…", systemImage: "info.circle", action: informationAction)
                    if section == .contents {
                        Button("Add Contents Item", systemImage: "plus", action: addItem)
                        Divider()
                        Button("Expand All", systemImage: "chevron.down.2", action: expandAll)
                        Button("Collapse All", systemImage: "chevron.right.2", action: collapseAll)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if section == .contents {
                contents
            } else {
                previews
            }
        }
        .background(.background)
        .onChange(of: isEditing) {
            if isEditing { section = .contents }
        }
        .onAppear(perform: initializeCollapsedItemsIfNeeded)
        .onChange(of: items, initializeCollapsedItemsIfNeeded)
    }

    @ViewBuilder
    private var contents: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label("No Contents", systemImage: "list.bullet")
            } description: {
                Text("Add sections to build navigation for this PDF.")
            } actions: {
                Button("Add Section", action: addItem)
            }
        } else if isEditing {
            List {
                ForEach($items) { $item in
                    HStack(spacing: 7) {
                        TextField("Section title", text: $item.title)
                        TextField(
                            "Page",
                            value: Binding(
                                get: { item.pageIndex + 1 },
                                set: { item.pageIndex = min(max(0, $0 - 1), max(0, pageCount - 1)) }
                            ),
                            format: .number
                        )
                        .frame(width: 48)
                        .multilineTextAlignment(.trailing)
                        Button(role: .destructive) {
                            removeItem(id: item.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, CGFloat(item.depth * 10))
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom) {
                Button(action: addItem) {
                    Label("Add Section", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(10)
                .background(.bar)
            }
        } else {
            List(visibleItems) { item in
                HStack(spacing: 5) {
                    if parentItemIDs.contains(item.id) {
                        Button {
                            toggleExpanded(item.id)
                        } label: {
                            Image(systemName: collapsedItemIDs.contains(item.id) ? "chevron.right" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .frame(width: 14)
                        }
                        .buttonStyle(.plain)
                        .help(collapsedItemIDs.contains(item.id) ? "Expand section" : "Collapse section")
                    } else {
                        Color.clear.frame(width: 14, height: 1)
                    }

                    Button {
                        jumpAction(item.pageIndex)
                    } label: {
                        HStack(spacing: 8) {
                        Text(item.title)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(item.pageIndex + 1)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                        .foregroundStyle(item.pageIndex == currentPage ? Color.orange : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, CGFloat(item.depth * 10))
                .listRowBackground(
                    item.pageIndex == currentPage
                        ? Color.secondary.opacity(0.12)
                        : Color.clear
                )
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var previews: some View {
        if let url, pageCount > 0 {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(0..<pageCount, id: \.self) { pageIndex in
                        Button {
                            jumpAction(pageIndex)
                        } label: {
                            VStack(spacing: 5) {
                                PDFPageThumbnail(url: url, pageIndex: pageIndex)
                                    .frame(maxWidth: 180)
                                    .aspectRatio(0.74, contentMode: .fit)
                                    .background(.white)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(
                                                pageIndex == currentPage ? Color.orange : Color.secondary.opacity(0.25),
                                                lineWidth: pageIndex == currentPage ? 3 : 1
                                            )
                                    }
                                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                                Text("Page \(pageIndex + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(pageIndex == currentPage ? Color.orange : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .background(Color.secondary.opacity(0.06))
        } else {
            ProgressView("Loading previews…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func addItem() {
        section = .contents
        isEditing = true
        items.append(PDFOutlineItem(title: "New section", pageIndex: currentPage, depth: 0))
    }

    private func removeItem(id: UUID) {
        collapsedItemIDs.remove(id)
        items.removeAll { $0.id == id }
    }

    private var parentItemIDs: Set<UUID> {
        Set(items.indices.compactMap { index in
            guard items.indices.contains(index + 1),
                  items[index + 1].depth > items[index].depth else { return nil }
            return items[index].id
        })
    }

    private var visibleItems: [PDFOutlineItem] {
        var result: [PDFOutlineItem] = []
        var hiddenBelowDepth: Int?

        for item in items {
            if let hiddenDepth = hiddenBelowDepth, item.depth <= hiddenDepth {
                hiddenBelowDepth = nil
            } else if hiddenBelowDepth != nil {
                continue
            }

            result.append(item)
            if collapsedItemIDs.contains(item.id) {
                hiddenBelowDepth = item.depth
            }
        }
        return result
    }

    private func initializeCollapsedItemsIfNeeded() {
        guard !hasInitializedCollapsedItems, !items.isEmpty else { return }
        collapsedItemIDs = collapseContents ? parentItemIDs : []
        hasInitializedCollapsedItems = true
    }

    private func toggleExpanded(_ id: UUID) {
        if collapsedItemIDs.contains(id) {
            collapsedItemIDs.remove(id)
        } else {
            collapsedItemIDs.insert(id)
        }
    }

    private func expandAll() {
        collapsedItemIDs.removeAll()
    }

    private func collapseAll() {
        collapsedItemIDs = parentItemIDs
    }
}

private struct BookmarksPopover: View {
    let bookmarks: [PageBookmark]
    let jumpAction: (Int) -> Void
    let deleteAction: (PageBookmark) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bookmarks").font(.headline)
            if bookmarks.isEmpty {
                Text("Bookmark a page to return to it quickly.")
                    .foregroundStyle(.secondary)
            } else {
                List(bookmarks.sorted { $0.pageIndex < $1.pageIndex }) { bookmark in
                    HStack {
                        Button(bookmark.title) { jumpAction(bookmark.pageIndex) }
                            .buttonStyle(.plain)
                        Spacer()
                        Button(role: .destructive) { deleteAction(bookmark) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding()
        .frame(width: 300, height: 320)
    }
}

private struct PageJumpPopover: View {
    @Binding var pageText: String
    let pageCount: Int
    let jumpAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jump to Page").font(.headline)
            HStack {
                TextField("Page", text: $pageText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(jumpAction)
                Text("of \(pageCount)").foregroundStyle(.secondary)
                Button("Go", action: jumpAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

private struct PDFInformationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let document: LibraryDocument
    @State private var title: String
    @State private var author: String
    @State private var subject: String
    @State private var sourceLink: String
    @State private var saveError: String?

    init(document: LibraryDocument) {
        self.document = document
        _title = State(initialValue: document.title)
        _author = State(initialValue: document.author)
        _subject = State(initialValue: document.subject)
        _sourceLink = State(initialValue: document.sourceLink)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PDF Information")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text(document.originalFileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                informationRow("Title", text: $title, prompt: "Document title")
                informationRow("Author", text: $author, prompt: "Author name")
                informationRow("Subject", text: $subject, prompt: "Subject or description")
                informationRow("Link", text: $sourceLink, prompt: "https://example.com")
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 440, idealWidth: 620)
        .alert("Couldn’t save PDF information", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Unknown error")
        }
    }

    private func informationRow(_ label: String, text: Binding<String>, prompt: String) -> some View {
        GridRow {
            Text("\(label):")
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 300)
        }
    }

    private func save() {
        document.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        document.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        document.sourceLink = sourceLink.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
#endif

private struct GenericReaderPane: View {
    let document: LibraryDocument

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(document.fileExtension.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.foliageGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.foliageGreen.opacity(0.1), in: Capsule())
                Text(document.originalFileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.bar)

            GenericDocumentContent(document: document)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct GenericDocumentContent: View {
    let document: LibraryDocument
    @State private var text = ""
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if document.fileExtension == "epub" {
                ContentUnavailableView(
                    "EPUB preview is postponed",
                    systemImage: "books.vertical",
                    description: Text("PDF reading and annotation are the current priority.")
                )
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t open this file",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else if isLoading {
                ProgressView("Opening document…")
            } else if text.isEmpty {
                ContentUnavailableView(
                    "This document is empty",
                    systemImage: "doc",
                    description: Text("There is no text to display.")
                )
            } else {
                ScrollView {
                    Text(renderedText)
                        .font(.system(.body, design: document.fileExtension == "tex" ? .monospaced : .serif))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                }
                .background(Color.foliagePaper)
            }
        }
        .task(id: document.storedFileName) { loadText() }
    }

    private var renderedText: AttributedString {
        guard ["md", "markdown"].contains(document.fileExtension) else {
            return AttributedString(text)
        }
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    private func loadText() {
        isLoading = true
        loadError = nil
        do {
            let data = try Data(contentsOf: DocumentStorage.fileURL(for: document))
            if let decoded = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) {
                text = decoded
            } else {
                loadError = "The file’s text encoding is not supported."
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

private struct NotesPane: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: LibraryDocument
    let pageIndex: Int?
    var selectedAnnotationID: UUID? = nil

    @State private var isShowingSummary = false

    private var freeNotes: [MarginNote] {
        (document.notes ?? [])
            .filter { pageIndex == nil || $0.pageIndex == nil || $0.pageIndex == pageIndex }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var sideNotes: [ReaderAnnotation] {
        (document.annotations ?? [])
            .filter { $0.kind == .sideNote && (pageIndex == nil || $0.pageIndex == pageIndex) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Side Notes")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text(pageIndex.map { "Page \($0 + 1)" } ?? "Document notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { isShowingSummary = true } label: {
                    Image(systemName: "text.alignleft")
                }
                .help("Book summary")
                Button(action: addFreeNote) {
                    Image(systemName: "plus")
                }
                .help("Add a free note to this page")
            }
            .buttonStyle(.bordered)
            .padding(18)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if sideNotes.isEmpty && freeNotes.isEmpty {
                            Text("Select a passage to attach a side note, or add a free note for this page.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }

                        ForEach(sideNotes) { annotation in
                            AnchoredNoteCard(
                                annotation: annotation,
                                isSelected: selectedAnnotationID == annotation.id
                            ) {
                                modelContext.delete(annotation)
                            }
                            .id(annotation.id)
                        }
                        ForEach(freeNotes) { note in
                            FreeNoteCard(note: note) {
                                modelContext.delete(note)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
                .onChange(of: selectedAnnotationID) { _, annotationID in
                    guard let annotationID else { return }
                    withAnimation { proxy.scrollTo(annotationID, anchor: .center) }
                }
            }
        }
        .background(.background)
        .sheet(isPresented: $isShowingSummary) {
            SummaryEditor(document: document)
        }
    }

    private func addFreeNote() {
        let note = MarginNote(pageIndex: pageIndex)
        document.notes = (document.notes ?? []) + [note]
        modelContext.insert(note)
    }
}

private struct AnchoredNoteCard: View {
    @Bindable var annotation: ReaderAnnotation
    let isSelected: Bool
    let deleteAction: () -> Void

    @State private var isShowingExpandedEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Page \(annotation.pageIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.foliageGreen)
                Spacer()
                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            Text(annotation.selectedText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .padding(.leading, 9)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color(annotationHex: annotation.colorHex)).frame(width: 2)
                }
            if NoteLength.isLong(annotation.noteBody) {
                CollapsedNotePreview(text: annotation.noteBody) {
                    isShowingExpandedEditor = true
                }
            } else {
                MarkdownEditor(
                    text: $annotation.noteBody,
                    placeholder: "Add a Markdown note…",
                    minHeight: 70
                )
                    .onChange(of: annotation.noteBody) { annotation.updatedAt = Date() }
            }
        }
        .padding(12)
        .background(Color(annotationHex: annotation.colorHex).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(annotationHex: annotation.colorHex).opacity(isSelected ? 0.95 : 0), lineWidth: 3)
        }
        .shadow(color: Color(annotationHex: annotation.colorHex).opacity(isSelected ? 0.3 : 0), radius: 10)
        .sheet(isPresented: $isShowingExpandedEditor) {
            ExpandedNoteEditor(
                title: "Side Note",
                subtitle: "Page \(annotation.pageIndex + 1)",
                quote: annotation.selectedText,
                text: $annotation.noteBody
            )
            .onChange(of: annotation.noteBody) { annotation.updatedAt = Date() }
        }
    }
}

private struct FreeNoteCard: View {
    @Bindable var note: MarginNote
    let deleteAction: () -> Void

    @State private var isShowingExpandedEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.pageIndex.map { "Page \($0 + 1)" } ?? "Document note")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
            if NoteLength.isLong(note.body) {
                CollapsedNotePreview(text: note.body) {
                    isShowingExpandedEditor = true
                }
            } else {
                MarkdownEditor(
                    text: $note.body,
                    placeholder: "Add a Markdown note…",
                    minHeight: 80
                )
                    .onChange(of: note.body) { note.updatedAt = Date() }
            }
        }
        .padding(12)
        .background(Color.foliageGreen.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .sheet(isPresented: $isShowingExpandedEditor) {
            ExpandedNoteEditor(
                title: "Free Note",
                subtitle: note.pageIndex.map { "Page \($0 + 1)" } ?? "Document note",
                text: $note.body
            )
            .onChange(of: note.body) { note.updatedAt = Date() }
        }
    }
}

private enum NoteLength {
    static func isLong(_ text: String) -> Bool {
        text.count > 280 || text.split(separator: "\n", omittingEmptySubsequences: false).count > 6
    }
}

private struct CollapsedNotePreview: View {
    let text: String
    let expandAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MathMarkdownView(text, maximumSourceLines: 5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture(perform: expandAction)

            Button(action: expandAction) {
                Label("Expand note", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.foliageGreen)
        }
        .padding(10)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ExpandedNoteEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    var quote: String?
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            if let quote, !quote.isEmpty {
                Text(quote)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.orange).frame(width: 3)
                    }
            }

            MarkdownEditor(
                text: $text,
                placeholder: "Add a Markdown note…",
                minHeight: 300
            )
        }
        .padding(24)
        .frame(minWidth: 460, idealWidth: 680, minHeight: 480)
    }
}

private struct SummaryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: LibraryDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Book Summary")
                        .font(.system(.title2, design: .serif, weight: .semibold))
                    Text(document.title)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            MarkdownEditor(
                text: $document.summary,
                placeholder: "Build the book summary in Markdown…",
                minHeight: 300
            )
        }
        .padding(24)
        .frame(minWidth: 460, idealWidth: 640, minHeight: 420)
    }
}
