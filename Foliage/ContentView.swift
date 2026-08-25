import SwiftData
import SwiftUI
import UniformTypeIdentifiers

#if canImport(PDFKit) && (os(macOS) || os(iOS))
import PDFKit
#endif

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LibraryDocument.importedAt, order: .reverse)
    private var documents: [LibraryDocument]
    @Query(sort: \LibraryCollection.name)
    private var collections: [LibraryCollection]
    @Query(sort: \LibraryTag.name)
    private var tags: [LibraryTag]

    @State private var selection: LibraryDocument?
    @State private var libraryFilter = LibraryFilter.all
    @State private var librarySort = LibrarySort.lastOpened
    @State private var searchText = ""
    @State private var isImporting = false
    @State private var renameTarget: LibraryDocument?
    @State private var renameText = ""
    @State private var metadataTarget: LibraryDocument?
    @State private var deleteTarget: LibraryDocument?
    @State private var isShowingSettings = false
    @State private var isCreatingCollection = false
    @State private var collectionName = ""
    @State private var appError: String?
    @State private var splitViewVisibility = NavigationSplitViewVisibility.all

    let storageWarning: String?

    init(storageWarning: String? = nil) {
        self.storageWarning = storageWarning
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            LibrarySidebar(
                selection: $libraryFilter,
                documents: documents,
                collections: collections,
                tags: tags,
                showLibraryAction: { selection = nil },
                createCollectionAction: {
                    collectionName = ""
                    isCreatingCollection = true
                },
                settingsAction: { isShowingSettings = true }
            )
            .navigationTitle("Foliage")
        } detail: {
            if let selection {
                ReaderWorkspace(
                    document: selection,
                    libraryAction: {
                        self.selection = nil
                        splitViewVisibility = .all
                    }
                )
            } else {
                LibraryBrowser(
                    documents: filteredDocuments,
                    selection: $selection,
                    title: filterTitle,
                    isSearching: !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    clearSearchAction: { searchText = "" },
                    renameAction: beginRename,
                    metadataAction: { metadataTarget = $0 },
                    deleteAction: { deleteTarget = $0 },
                    statusAction: setStatus,
                    revealAction: reveal
                )
                .searchable(text: $searchText, placement: .toolbar, prompt: "Search library")
                .toolbar { libraryToolbar }
            }
        }
        .tint(.foliageGreen)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: DocumentStorage.importableTypes,
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
        .alert("Rename Book", isPresented: renamePresentation) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename", action: finishRename)
                .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("New Collection", isPresented: $isCreatingCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create", action: createCollection)
                .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Delete \(deleteTarget?.title ?? "this book")?",
            isPresented: deletePresentation,
            titleVisibility: .visible
        ) {
            Button("Delete Book and Notes", role: .destructive) {
                if let deleteTarget { delete(deleteTarget) }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This removes the imported copy, highlights, notes, and reading progress.")
        }
        .sheet(item: $metadataTarget) { document in
            DocumentMetadataEditor(
                document: document,
                allTags: tags,
                collections: collections,
                saveAction: saveMetadata
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            AppSettingsView()
        }
        .alert("Foliage", isPresented: errorPresentation) {
            Button("OK", role: .cancel) { appError = nil }
        } message: {
            Text(appError ?? "Unknown error")
        }
        .onChange(of: libraryFilter) {
            guard let selection, !filteredDocuments.contains(where: { $0.id == selection.id }) else { return }
            self.selection = nil
        }
        .onChange(of: selection?.id) {
            splitViewVisibility = selection == nil ? .all : .detailOnly
        }
        .safeAreaInset(edge: .top) {
            if let storageWarning {
                Label(storageWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange)
            }
        }
        .focusedSceneValue(\.libraryCommandActions, LibraryCommandActions(
            importDocument: { isImporting = true },
            showLibrary: {
                selection = nil
                splitViewVisibility = .all
            },
            toggleLibrarySidebar: {
                splitViewVisibility = splitViewVisibility == .detailOnly ? .all : .detailOnly
            },
            showSettings: { isShowingSettings = true }
        ))
    }

    private var filteredDocuments: [LibraryDocument] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = documents.filter { document in
            matchesFilter(document) && (query.isEmpty || matchesSearch(document, query: query))
        }
        return filtered.sorted(by: librarySort.areInIncreasingOrder)
    }

    private var filterTitle: String {
        if case .collection(let id) = libraryFilter {
            return collections.first(where: { $0.id == id })?.name ?? "Collection"
        }
        return libraryFilter.title
    }

    private func matchesFilter(_ document: LibraryDocument) -> Bool {
        switch libraryFilter {
        case .all:
            true
        case .recent:
            document.hasBeenOpened
        case .status(let status):
            document.readingStatus == status
        case .fileType(let fileExtension):
            document.fileExtension == fileExtension
        case .collection(let id):
            document.collections?.contains { $0.id == id } == true
        case .tag(let name):
            document.tags?.contains { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame } == true
        }
    }

    private func matchesSearch(_ document: LibraryDocument, query: String) -> Bool {
        let normalizedQuery = query.normalizedForLibrarySearch
        guard !normalizedQuery.isEmpty else { return true }

        let searchableText = ([
            document.title,
            document.author,
            document.subject,
            document.sourceLink,
            document.originalFileName,
            document.fileExtension,
            document.readingStatus.title,
            document.summary,
        ]
        + (document.tags ?? []).map(\.name)
        + (document.notes ?? []).map(\.body)
        + (document.annotations ?? []).flatMap { [$0.selectedText, $0.noteBody] })
            .joined(separator: " ")
            .normalizedForLibrarySearch

        if searchableText.contains(normalizedQuery) { return true }

        let candidateWords = searchableText.split(separator: " ").map(String.init)
        return normalizedQuery.split(separator: " ").allSatisfy { queryWord in
            candidateWords.contains { $0.fuzzyMatchesLibraryWord(String(queryWord)) }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 4) {
                Menu {
                    ForEach(LibrarySort.allCases) { sort in
                        Button {
                            librarySort = sort
                        } label: {
                            Label(sort.title, systemImage: sort.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: librarySort.systemImage)
                }
                .help("Sort by \(librarySort.title)")
                .accessibilityLabel("Sort by \(librarySort.title)")

                Button {
                    isImporting = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Import documents")
                .accessibilityLabel("Import documents")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private var renamePresentation: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deletePresentation: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var errorPresentation: Binding<Bool> {
        Binding(
            get: { appError != nil },
            set: { if !$0 { appError = nil } }
        )
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        var imported: [LibraryDocument] = []
        do {
            for url in try result.get() {
                let document = try DocumentStorage.importDocument(from: url)
                modelContext.insert(document)
                imported.append(document)
            }
            try modelContext.save()
            libraryFilter = .all
            selection = imported.first
        } catch {
            for document in imported {
                try? DocumentStorage.removeFile(for: document)
                modelContext.delete(document)
            }
            appError = "Couldn’t import the selected documents. \(error.localizedDescription)"
        }
    }

    private func beginRename(_ document: LibraryDocument) {
        renameText = document.title
        renameTarget = document
    }

    private func finishRename() {
        guard let renameTarget else { return }
        renameTarget.title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        saveContext()
        self.renameTarget = nil
    }

    private func setStatus(_ status: ReadingStatus, for document: LibraryDocument) {
        document.readingStatus = status
        if status == .finished {
            document.readingProgress = 1
        }
        saveContext()
    }

    private func saveMetadata(
        for document: LibraryDocument,
        author: String,
        coverStyle: CoverStyle,
        customCoverData: Data?,
        tagNames: [String],
        collectionIDs: Set<UUID>
    ) {
        document.author = author.trimmingCharacters(in: .whitespacesAndNewlines)
        document.coverStyle = coverStyle
        document.customCoverData = customCoverData
        document.tags = tagNames.map { name in
            if let existing = tags.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                return existing
            }
            let tag = LibraryTag(name: name)
            modelContext.insert(tag)
            return tag
        }
        document.collections = collections.filter { collectionIDs.contains($0.id) }
        saveContext()
        metadataTarget = nil
    }

    private func createCollection() {
        let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !collections.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            appError = "A collection named \"\(name)\" already exists."
            return
        }
        modelContext.insert(LibraryCollection(name: name))
        saveContext()
    }

    private func delete(_ document: LibraryDocument) {
        do {
            try DocumentStorage.removeFile(for: document)
            if selection?.id == document.id {
                selection = nil
            }
            modelContext.delete(document)
            try modelContext.save()
        } catch {
            appError = "Couldn’t delete \"\(document.title)\". \(error.localizedDescription)"
        }
        deleteTarget = nil
    }

    private func reveal(_ document: LibraryDocument) {
#if os(macOS)
        do {
            NSWorkspace.shared.activateFileViewerSelecting([try DocumentStorage.fileURL(for: document)])
        } catch {
            appError = error.localizedDescription
        }
#endif
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            appError = "Couldn’t save the library. \(error.localizedDescription)"
        }
    }
}

private enum LibraryFilter: Hashable {
    case all
    case recent
    case status(ReadingStatus)
    case fileType(String)
    case collection(UUID)
    case tag(String)

    var title: String {
        switch self {
        case .all: "All Books"
        case .recent: "Recent"
        case .status(let status): status.title
        case .fileType("pdf"): "PDFs"
        case .fileType("epub"): "EPUBs"
        case .fileType(let type): type.uppercased()
        case .collection: "Collection"
        case .tag(let name): name
        }
    }
}

private enum LibrarySort: String, CaseIterable, Identifiable {
    case lastOpened
    case imported
    case title
    case progress

    var id: Self { self }

    var title: String {
        switch self {
        case .lastOpened: "Last Opened"
        case .imported: "Date Added"
        case .title: "Title"
        case .progress: "Progress"
        }
    }

    var systemImage: String {
        switch self {
        case .lastOpened: "clock"
        case .imported: "calendar.badge.plus"
        case .title: "textformat"
        case .progress: "chart.bar.fill"
        }
    }

    func areInIncreasingOrder(_ lhs: LibraryDocument, _ rhs: LibraryDocument) -> Bool {
        switch self {
        case .lastOpened:
            if lhs.lastOpenedAt != rhs.lastOpenedAt { return lhs.lastOpenedAt > rhs.lastOpenedAt }
        case .imported:
            if lhs.importedAt != rhs.importedAt { return lhs.importedAt > rhs.importedAt }
        case .title:
            let result = lhs.title.localizedStandardCompare(rhs.title)
            if result != .orderedSame { return result == .orderedAscending }
        case .progress:
            if lhs.readingProgress != rhs.readingProgress { return lhs.readingProgress > rhs.readingProgress }
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private struct LibrarySidebar: View {
    @Binding var selection: LibraryFilter
    let documents: [LibraryDocument]
    let collections: [LibraryCollection]
    let tags: [LibraryTag]
    let showLibraryAction: () -> Void
    let createCollectionAction: () -> Void
    let settingsAction: () -> Void

    @StateObject private var cloudSync = CloudSyncMonitor()

    var body: some View {
        List {
            Section("Library") {
                sidebarRow("All Books", systemImage: "books.vertical", count: documents.count, filter: .all)
                sidebarRow(
                    "Recent",
                    systemImage: "clock",
                    count: documents.count(where: \.hasBeenOpened),
                    filter: .recent
                )
            }

            Section("Reading") {
                ForEach(ReadingStatus.allCases) { status in
                    sidebarRow(
                        status.title,
                        systemImage: status.systemImage,
                        count: documents.count { $0.readingStatus == status },
                        filter: .status(status)
                    )
                }
            }

            Section("Formats") {
                sidebarRow("PDFs", systemImage: "doc.richtext", count: count(for: "pdf"), filter: .fileType("pdf"))
                sidebarRow("EPUBs", systemImage: "text.book.closed", count: count(for: "epub"), filter: .fileType("epub"))
            }

            if !displayTags.isEmpty {
                Section("Tags") {
                    ForEach(displayTags) { tag in
                        sidebarRow(
                            tag.name,
                            systemImage: "tag",
                            count: documents.count { document in
                                document.tags?.contains {
                                    $0.name.localizedCaseInsensitiveCompare(tag.name) == .orderedSame
                                } == true
                            },
                            filter: .tag(tag.name)
                        )
                    }
                }
            }

            Section {
                ForEach(collections) { collection in
                    sidebarRow(
                        collection.name,
                        systemImage: "rectangle.stack",
                        count: collection.documents?.count ?? 0,
                        filter: .collection(collection.id)
                    )
                }
                Button(action: createCollectionAction) {
                    HStack {
                        Image(systemName: "plus")
                            .frame(width: 22)
                        Text("New Collection")
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.foliageGreen)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            } header: {
                Text("Collections")
            }

            Section("Account") {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: cloudSync.state.systemImage)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(cloudSync.state.title)
                            .font(.callout.weight(.semibold))
                        Text(cloudSync.state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 3)
                .listRowInsets(EdgeInsets(top: 2, leading: 18, bottom: 2, trailing: 8))
            }

            Section("Application") {
                Button(action: settingsAction) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 340)
        .task { await cloudSync.refresh() }
    }

    private func sidebarRow(
        _ title: String,
        systemImage: String,
        count: Int,
        filter: LibraryFilter
    ) -> some View {
        Button {
            selection = filter
            showLibraryAction()
        } label: {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 22, alignment: .center)
                Text(title)
                    .lineLimit(1)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(selection == filter ? .white.opacity(0.78) : .secondary)
            }
            .foregroundStyle(selection == filter ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                selection == filter ? Color.foliageGreen : Color.clear,
                in: RoundedRectangle(cornerRadius: 9)
            )
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
    }

    private func count(for fileExtension: String) -> Int {
        documents.count { $0.fileExtension == fileExtension }
    }

    private var displayTags: [LibraryTag] {
        var names: Set<String> = []
        return tags
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .filter { names.insert($0.name.lowercased()).inserted }
    }
}

private struct LibraryBrowser: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let documents: [LibraryDocument]
    @Binding var selection: LibraryDocument?
    let title: String
    let isSearching: Bool
    let clearSearchAction: () -> Void
    let renameAction: (LibraryDocument) -> Void
    let metadataAction: (LibraryDocument) -> Void
    let deleteAction: (LibraryDocument) -> Void
    let statusAction: (ReadingStatus, LibraryDocument) -> Void
    let revealAction: (LibraryDocument) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 24)]

    var body: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView {
                    Label(isSearching ? "No matching books" : "No books here", systemImage: isSearching ? "magnifyingglass" : "books.vertical")
                } description: {
                    Text(isSearching ? "Try a shorter title, file name, tag, or note." : "Choose another library section or use + to import a document.")
                } actions: {
                    if isSearching {
                        Button("Clear Search", action: clearSearchAction)
                    }
                }
            } else if horizontalSizeClass == .compact {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(documents) { document in
                            documentLink(document) {
                                LibraryDocumentRow(document: document)
                            }
                            Divider().padding(.leading, 76)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .background(Color.foliageLibraryBackground)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                        ForEach(documents) { document in
                            documentLink(document) {
                                LibraryDocumentCard(document: document)
                            }
                        }
                    }
                    .padding(28)
                }
                .background(Color.foliageLibraryBackground)
            }
        }
        .navigationTitle(title)
    }

    private func documentLink<CardContent: View>(
        _ document: LibraryDocument,
        @ViewBuilder label: () -> CardContent
    ) -> some View {
        Button {
            selection = document
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { selection = document }
            Button("Rename", systemImage: "pencil") { renameAction(document) }
            Menu("Reading Status", systemImage: "book.pages") {
                ForEach(ReadingStatus.allCases) { status in
                    Button {
                        statusAction(status, document)
                    } label: {
                        Label(status.title, systemImage: status.systemImage)
                    }
                }
            }
            Button("Edit Book Details", systemImage: "info.circle") { metadataAction(document) }
#if os(macOS)
            Divider()
            Button("Reveal in Finder", systemImage: "folder") { revealAction(document) }
#endif
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { deleteAction(document) }
        }
    }
}

private struct LibraryDocumentCard: View {
    let document: LibraryDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DocumentCover(document: document)
                .aspectRatio(0.72, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 5)

            Text(document.title)
                .font(.system(.headline, design: .serif, weight: .semibold))
                .lineLimit(2, reservesSpace: true)

            if !document.author.isEmpty {
                Text(document.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Label(document.readingStatus.title, systemImage: document.readingStatus.systemImage)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(document.fileExtension.uppercased())
                    .fontWeight(.bold)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            ProgressView(value: document.readingProgress)
                .tint(statusColor)
        }
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        document.readingStatus == .finished ? .green : .foliageGreen
    }
}

private struct LibraryDocumentRow: View {
    let document: LibraryDocument

    var body: some View {
        HStack(spacing: 14) {
            DocumentCover(document: document)
                .frame(width: 48, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 5) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(2)
                if !document.author.isEmpty {
                    Text(document.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Label(document.readingStatus.title, systemImage: document.readingStatus.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: document.readingProgress)
                    .tint(Color.foliageGreen)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DocumentCover: View {
    let document: LibraryDocument

    var body: some View {
        ZStack {
            LinearGradient(
                colors: coverColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            themeCover

#if canImport(PDFKit) && (os(macOS) || os(iOS))
            if document.coverStyle == .automatic && document.fileExtension == "pdf" {
                PDFCoverThumbnail(document: document)
            }
#endif

            if document.coverStyle == .custom, let customCoverData = document.customCoverData {
                CoverImageDataView(data: customCoverData)
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.black.opacity(0.13))
                .frame(width: 4)
        }
        .accessibilityLabel("Cover of \(document.title)")
    }

    private var themeCover: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .light))
            Text(document.title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
                .lineLimit(6)
            if !document.author.isEmpty {
                Text(document.author)
                    .font(.system(size: 13, weight: .medium, design: .serif))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(0.82)
            }
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(20)
    }

    private var coverColors: [Color] {
        switch document.fileExtension {
        case "pdf": [Color(red: 0.28, green: 0.12, blue: 0.12), Color(red: 0.62, green: 0.25, blue: 0.17)]
        case "epub": [Color(red: 0.08, green: 0.25, blue: 0.2), Color(red: 0.24, green: 0.5, blue: 0.34)]
        case "md", "markdown": [Color(red: 0.12, green: 0.2, blue: 0.3), Color(red: 0.24, green: 0.42, blue: 0.55)]
        case "tex": [Color(red: 0.25, green: 0.18, blue: 0.34), Color(red: 0.5, green: 0.35, blue: 0.6)]
        default: [Color(red: 0.24, green: 0.22, blue: 0.18), Color(red: 0.53, green: 0.44, blue: 0.3)]
        }
    }

    private var iconName: String {
        switch document.fileExtension {
        case "pdf": "doc.richtext"
        case "md", "markdown": "text.document"
        case "tex": "function"
        case "epub": "books.vertical"
        default: "doc.text"
        }
    }
}

private struct CoverImageDataView: View {
    let data: Data

    var body: some View {
        Group {
#if os(macOS)
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
#elseif os(iOS)
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
#else
            Color.clear
#endif
        }
        .clipped()
    }
}

#if canImport(PDFKit) && (os(macOS) || os(iOS))
private struct PDFCoverThumbnail: View {
    let document: LibraryDocument

#if os(macOS)
    @State private var image: NSImage?
#else
    @State private var image: UIImage?
#endif

    var body: some View {
        ZStack {
            Color.clear

            if let image {
#if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
#else
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
#endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: document.storedFileName) {
            guard let url = try? DocumentStorage.fileURL(for: document),
                  let page = PDFDocument(url: url)?.page(at: 0) else { return }
            image = page.thumbnail(of: CGSize(width: 360, height: 500), for: .mediaBox)
        }
    }
}
#endif

private struct DocumentMetadataEditor: View {
    @Environment(\.dismiss) private var dismiss

    let document: LibraryDocument
    let allTags: [LibraryTag]
    let collections: [LibraryCollection]
    let saveAction: (LibraryDocument, String, CoverStyle, Data?, [String], Set<UUID>) -> Void

    @State private var authorText: String
    @State private var coverStyle: CoverStyle
    @State private var customCoverData: Data?
    @State private var isChoosingCover = false
    @State private var pendingTagText = ""
    @State private var selectedTagNames: Set<String>
    @State private var selectedCollectionIDs: Set<UUID>

    init(
        document: LibraryDocument,
        allTags: [LibraryTag],
        collections: [LibraryCollection],
        saveAction: @escaping (LibraryDocument, String, CoverStyle, Data?, [String], Set<UUID>) -> Void
    ) {
        self.document = document
        self.allTags = allTags
        self.collections = collections
        self.saveAction = saveAction
        _authorText = State(initialValue: document.author)
        _coverStyle = State(initialValue: document.coverStyle)
        _customCoverData = State(initialValue: document.customCoverData)
        _selectedTagNames = State(initialValue: Set((document.tags ?? []).map(\.name)))
        _selectedCollectionIDs = State(initialValue: Set((document.collections ?? []).map(\.id)))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "book.closed.fill")
                    .font(.title2)
                    .foregroundStyle(Color.foliageGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Book Details")
                        .font(.title2.weight(.semibold))
                    Text(document.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailsSection("Book", systemImage: "person.text.rectangle") {
                        TextField("Author name", text: $authorText)
                            .textFieldStyle(.roundedBorder)
                    }

                    detailsSection("Cover", systemImage: "photo.on.rectangle") {
                        LazyVGrid(columns: selectionColumns, alignment: .leading, spacing: 8) {
                            ForEach(CoverStyle.allCases) { style in
                                selectionButton(
                                    title: style.title(for: document),
                                    systemImage: coverIcon(for: style),
                                    isSelected: coverStyle == style
                                ) {
                                    coverStyle = style
                                }
                            }
                        }

                        if coverStyle == .custom {
                            HStack(spacing: 16) {
                                if let customCoverData {
                                    CoverImageDataView(data: customCoverData)
                                        .frame(width: 72, height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                                Button(customCoverData == nil ? "Choose Image" : "Replace Image") {
                                    isChoosingCover = true
                }
            }
        }
    }

                    detailsSection("Tags", systemImage: "tag") {
                        HStack {
                            TextField("Add tags separated by commas", text: $pendingTagText)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addPendingTags)
                            Button(action: addPendingTags) {
                                Image(systemName: "plus")
                            }
                            .disabled(pendingTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        if !availableTagNames.isEmpty {
                            LazyVGrid(columns: selectionColumns, alignment: .leading, spacing: 8) {
                                ForEach(availableTagNames, id: \.self) { name in
                                    selectionButton(
                                        title: name,
                                        systemImage: "tag",
                                        isSelected: selectedTagNames.contains(name)
                                    ) {
                                        toggleTag(name)
                                    }
                                }
                            }
                        }
                    }

                    detailsSection("Collections", systemImage: "rectangle.stack") {
                        if collections.isEmpty {
                            Text("Create a collection from the library sidebar first.")
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: selectionColumns, alignment: .leading, spacing: 8) {
                                ForEach(collections) { collection in
                                    selectionButton(
                                        title: collection.name,
                                        systemImage: "rectangle.stack",
                                        isSelected: selectedCollectionIDs.contains(collection.id)
                                    ) {
                                        toggleCollection(collection.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    saveAction(
                        document,
                        authorText,
                        coverStyle,
                        customCoverData,
                        finalTagNames,
                        selectedCollectionIDs
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
#if os(macOS)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 620)
#else
        .frame(minHeight: 520)
#endif
        .fileImporter(
            isPresented: $isChoosingCover,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: loadCustomCover
        )
    }

    private let selectionColumns = [GridItem(.adaptive(minimum: 140), spacing: 8)]

    private var availableTagNames: [String] {
        var seen: Set<String> = []
        return (allTags.map(\.name) + Array(selectedTagNames))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    private var finalTagNames: [String] {
        var names = selectedTagNames
        for name in parsedPendingTags {
            names.insert(name)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var parsedPendingTags: [String] {
        pendingTagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func addPendingTags() {
        selectedTagNames.formUnion(parsedPendingTags)
        pendingTagText = ""
    }

    private func toggleTag(_ name: String) {
        if selectedTagNames.contains(name) {
            selectedTagNames.remove(name)
        } else {
            selectedTagNames.insert(name)
        }
    }

    private func toggleCollection(_ id: UUID) {
        if selectedCollectionIDs.contains(id) {
            selectedCollectionIDs.remove(id)
        } else {
            selectedCollectionIDs.insert(id)
        }
    }

    private func coverIcon(for style: CoverStyle) -> String {
        switch style {
        case .automatic: "doc.richtext"
        case .theme: "textformat.size"
        case .custom: "photo"
        }
    }

    private func detailsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.foliageGreen)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func selectionButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : systemImage)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.foliageGreen.opacity(0.16) : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.foliageGreen.opacity(0.65) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.foliageGreen : .primary)
    }

    private func loadCustomCover(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        if let data = try? Data(contentsOf: url) {
            customCoverData = data
            coverStyle = .custom
        }
    }
}

extension Color {
    static let foliageGreen = Color(red: 0.18, green: 0.39, blue: 0.27)
    static let foliagePaper = Color(red: 0.97, green: 0.95, blue: 0.89)
    static let foliageLibraryBackground = Color(red: 0.945, green: 0.936, blue: 0.905)
}

private extension String {
    var normalizedForLibrarySearch: String {
        let folded = folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let separatedWords = String(folded.map { character in
            character.isLetter || character.isNumber ? character : " "
        })
        return separatedWords
            .split(separator: " ")
            .map(String.init)
            .joined(separator: " ")
    }

    func fuzzyMatchesLibraryWord(_ query: String) -> Bool {
        if contains(query) || query.contains(self) { return true }
        guard query.count >= 4, abs(count - query.count) <= 2 else { return false }
        let allowedDistance = query.count >= 8 ? 2 : 1
        return editDistance(to: query, limit: allowedDistance) <= allowedDistance
    }

    func editDistance(to other: String, limit: Int) -> Int {
        let source = Array(self)
        let target = Array(other)
        var previous = Array(0...target.count)

        for (sourceIndex, sourceCharacter) in source.enumerated() {
            var current = [sourceIndex + 1]
            var rowMinimum = current[0]
            for (targetIndex, targetCharacter) in target.enumerated() {
                let value = Swift.min(
                    current[targetIndex] + 1,
                    previous[targetIndex + 1] + 1,
                    previous[targetIndex] + (sourceCharacter == targetCharacter ? 0 : 1)
                )
                current.append(value)
                rowMinimum = Swift.min(rowMinimum, value)
            }
            if rowMinimum > limit { return rowMinimum }
            previous = current
        }
        return previous[target.count]
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [
                LibraryDocument.self,
                MarginNote.self,
                ReaderAnnotation.self,
                PageBookmark.self,
                LibraryTag.self,
                LibraryCollection.self,
            ],
            inMemory: true
        )
}
