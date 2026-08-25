import Foundation
import UniformTypeIdentifiers

enum DocumentStorage {
    static let importableTypes: [UTType] = {
        let extensions = ["pdf", "md", "markdown", "txt", "text", "tex", "epub"]
        return extensions.compactMap { UTType(filenameExtension: $0) }
    }()

    static func importDocument(from sourceURL: URL) throws -> LibraryDocument {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let directory = try documentsDirectory()
        let fileExtension = sourceURL.pathExtension.lowercased()
        let storedFileName = fileExtension.isEmpty
            ? UUID().uuidString
            : "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(storedFileName)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        return LibraryDocument(
            title: baseName.isEmpty ? sourceURL.lastPathComponent : baseName,
            originalFileName: sourceURL.lastPathComponent,
            storedFileName: storedFileName,
            fileExtension: fileExtension
        )
    }

    static func fileURL(for document: LibraryDocument) throws -> URL {
        try documentsDirectory().appendingPathComponent(document.storedFileName)
    }

    static func removeFile(for document: LibraryDocument) throws {
        let url = try fileURL(for: document)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func replaceFile(for document: LibraryDocument, with sourceURL: URL) throws {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        guard sourceURL.pathExtension.lowercased() == document.fileExtension else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        let destinationURL = try fileURL(for: document)
        let replacementURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(UUID().uuidString).replacement")
        try FileManager.default.copyItem(at: sourceURL, to: replacementURL)

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: replacementURL)
            } else {
                try FileManager.default.moveItem(at: replacementURL, to: destinationURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: replacementURL)
            throw error
        }
    }

    private static func documentsDirectory() throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("Foliage", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
