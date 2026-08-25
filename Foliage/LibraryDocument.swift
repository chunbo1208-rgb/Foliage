import Foundation
import SwiftData

@Model
final class LibraryDocument {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var subject: String = ""
    var sourceLink: String = ""
    var originalFileName: String = ""
    var storedFileName: String = ""
    var fileExtension: String = ""
    var importedAt: Date = Date()
    var lastOpenedAt: Date = Date()
    var summary: String = ""
    var lastPageIndex: Int = 0
    var readingStatusRawValue: String = ReadingStatus.wantToRead.rawValue
    var readingProgress: Double = 0
    var totalPageCount: Int = 0
    var hasBeenOpened: Bool = false
    var coverStyleRawValue: String = CoverStyle.automatic.rawValue
    var pdfContentsJSON: String = ""
    @Attribute(.externalStorage) var customCoverData: Data?

    @Relationship(deleteRule: .cascade, inverse: \MarginNote.document)
    var notes: [MarginNote]? = []

    @Relationship(deleteRule: .cascade, inverse: \ReaderAnnotation.document)
    var annotations: [ReaderAnnotation]? = []

    @Relationship(deleteRule: .cascade, inverse: \PageBookmark.document)
    var bookmarks: [PageBookmark]? = []

    @Relationship(inverse: \LibraryTag.documents)
    var tags: [LibraryTag]? = []

    @Relationship(inverse: \LibraryCollection.documents)
    var collections: [LibraryCollection]? = []

    var readingStatus: ReadingStatus {
        get { ReadingStatus(rawValue: readingStatusRawValue) ?? .wantToRead }
        set { readingStatusRawValue = newValue.rawValue }
    }

    var coverStyle: CoverStyle {
        get { CoverStyle(rawValue: coverStyleRawValue) ?? .automatic }
        set { coverStyleRawValue = newValue.rawValue }
    }

    init(
        title: String,
        originalFileName: String,
        storedFileName: String,
        fileExtension: String
    ) {
        self.id = UUID()
        self.title = title
        self.author = ""
        self.subject = ""
        self.sourceLink = ""
        self.originalFileName = originalFileName
        self.storedFileName = storedFileName
        self.fileExtension = fileExtension
        self.importedAt = Date()
        self.lastOpenedAt = Date()
        self.summary = ""
        self.lastPageIndex = 0
        self.readingStatusRawValue = ReadingStatus.wantToRead.rawValue
        self.readingProgress = 0
        self.totalPageCount = 0
        self.hasBeenOpened = false
        self.coverStyleRawValue = CoverStyle.automatic.rawValue
        self.pdfContentsJSON = ""
        self.customCoverData = nil
        self.notes = []
        self.annotations = []
        self.bookmarks = []
        self.tags = []
        self.collections = []
    }
}

enum CoverStyle: String, CaseIterable, Identifiable {
    case automatic
    case theme
    case custom

    var id: Self { self }

    func title(for document: LibraryDocument) -> String {
        switch self {
        case .automatic:
            document.fileExtension == "pdf" ? "PDF First Page" : "Document Default"
        case .theme:
            "Theme Cover"
        case .custom:
            "Custom Image"
        }
    }
}

enum ReadingStatus: String, CaseIterable, Identifiable {
    case wantToRead
    case reading
    case finished

    var id: Self { self }

    var title: String {
        switch self {
        case .wantToRead: "Want to Read"
        case .reading: "Reading"
        case .finished: "Finished"
        }
    }

    var systemImage: String {
        switch self {
        case .wantToRead: "bookmark"
        case .reading: "book.pages"
        case .finished: "checkmark.circle"
        }
    }
}

@Model
final class LibraryTag {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var documents: [LibraryDocument]? = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.documents = []
    }
}

@Model
final class LibraryCollection {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var documents: [LibraryDocument]? = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.documents = []
    }
}

enum AnnotationKind: String, CaseIterable {
    case highlight
    case underline
    case sideNote
}

@Model
final class ReaderAnnotation {
    var id: UUID = UUID()
    var kindRawValue: String = AnnotationKind.highlight.rawValue
    var selectedText: String = ""
    var noteBody: String = ""
    var colorHex: String = "FFE052"
    var pageIndex: Int = 0
    var boundsX: Double = 0
    var boundsY: Double = 0
    var boundsWidth: Double = 0
    var boundsHeight: Double = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var document: LibraryDocument?

    var kind: AnnotationKind {
        get { AnnotationKind(rawValue: kindRawValue) ?? .highlight }
        set { kindRawValue = newValue.rawValue }
    }

    init(
        kind: AnnotationKind,
        selectedText: String,
        noteBody: String = "",
        colorHex: String = "FFE052",
        pageIndex: Int,
        bounds: CGRect,
        document: LibraryDocument? = nil
    ) {
        self.id = UUID()
        self.kindRawValue = kind.rawValue
        self.selectedText = selectedText
        self.noteBody = noteBody
        self.colorHex = colorHex
        self.pageIndex = pageIndex
        self.boundsX = bounds.origin.x
        self.boundsY = bounds.origin.y
        self.boundsWidth = bounds.size.width
        self.boundsHeight = bounds.size.height
        self.createdAt = Date()
        self.updatedAt = Date()
        self.document = document
    }
}

@Model
final class PageBookmark {
    var id: UUID = UUID()
    var pageIndex: Int = 0
    var title: String = ""
    var createdAt: Date = Date()
    var document: LibraryDocument?

    init(pageIndex: Int, title: String, document: LibraryDocument? = nil) {
        self.id = UUID()
        self.pageIndex = pageIndex
        self.title = title
        self.createdAt = Date()
        self.document = document
    }
}

@Model
final class MarginNote {
    var id: UUID = UUID()
    var body: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var pageIndex: Int?
    var document: LibraryDocument?

    init(body: String = "", pageIndex: Int? = nil, document: LibraryDocument? = nil) {
        self.id = UUID()
        self.body = body
        self.createdAt = Date()
        self.updatedAt = Date()
        self.pageIndex = pageIndex
        self.document = document
    }
}
