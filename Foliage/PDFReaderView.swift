import Foundation
import SwiftUI

#if canImport(PDFKit) && (os(macOS) || os(iOS))
import PDFKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct PDFSelectionSnapshot: Equatable {
    var text: String
    var pageIndex: Int
    var bounds: CGRect
    var actionAnchor: CGPoint
}

struct PDFAnnotationTap: Equatable {
    var annotationID: UUID
    var actionAnchor: CGPoint
}

struct PDFOutlineItem: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var pageIndex: Int
    var depth: Int
}

struct PDFSearchResult: Equatable, Identifiable, Sendable {
    let id: Int
    let pageIndex: Int
    let excerpt: String
}

enum PDFSearchLoader {
    nonisolated static func search(_ query: String, in url: URL) -> [PDFSearchResult] {
        guard let document = PDFDocument(url: url) else { return [] }

        return document.findString(query, withOptions: .caseInsensitive).enumerated().map { index, match in
            guard let page = match.pages.first else {
                return PDFSearchResult(id: index, pageIndex: 0, excerpt: query)
            }

            let pageIndex = document.index(for: page)
            let matchBounds = match.bounds(for: page)
            let pageBounds = page.bounds(for: .cropBox)
            let contextBounds = CGRect(
                x: pageBounds.minX,
                y: matchBounds.minY - matchBounds.height,
                width: pageBounds.width,
                height: max(24, matchBounds.height * 3)
            ).intersection(pageBounds)
            let context = page.selection(for: contextBounds)?.string ?? match.string ?? query
            let excerpt = context
                .split(whereSeparator: \Character.isWhitespace)
                .joined(separator: " ")

            return PDFSearchResult(
                id: index,
                pageIndex: pageIndex,
                excerpt: excerpt.isEmpty ? query : excerpt
            )
        }
    }
}

enum PDFOutlineLoader {
    static func load(from url: URL) -> (items: [PDFOutlineItem], pageCount: Int) {
        guard let document = PDFDocument(url: url) else { return ([], 0) }
        var items: [PDFOutlineItem] = []

        if let root = document.outlineRoot {
            appendChildren(of: root, in: document, depth: 0, to: &items)
        }
        return (items, document.pageCount)
    }

    private static func appendChildren(
        of parent: PDFOutline,
        in document: PDFDocument,
        depth: Int,
        to items: inout [PDFOutlineItem]
    ) {
        for index in 0..<parent.numberOfChildren {
            guard let child = parent.child(at: index) else { continue }
            let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
            if let page = destination?.page {
                items.append(PDFOutlineItem(
                    title: child.label ?? "Untitled section",
                    pageIndex: document.index(for: page),
                    depth: depth
                ))
            }
            appendChildren(of: child, in: document, depth: depth + 1, to: &items)
        }
    }
}

#if os(macOS)
struct PDFContainer: NSViewRepresentable {
    let url: URL
    let annotations: [ReaderAnnotation]
    @Binding var currentPage: Int
    @Binding var pageCount: Int
    @Binding var selection: PDFSelectionSnapshot?
    @Binding var annotationTap: PDFAnnotationTap?

    func makeCoordinator() -> PDFViewCoordinator { PDFViewCoordinator(parent: self) }

    func makeNSView(context: Context) -> PDFView {
        makePDFView(coordinator: context.coordinator)
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        updatePDFView(view, coordinator: context.coordinator)
    }
}
#else
struct PDFContainer: UIViewRepresentable {
    let url: URL
    let annotations: [ReaderAnnotation]
    @Binding var currentPage: Int
    @Binding var pageCount: Int
    @Binding var selection: PDFSelectionSnapshot?
    @Binding var annotationTap: PDFAnnotationTap?

    func makeCoordinator() -> PDFViewCoordinator { PDFViewCoordinator(parent: self) }

    func makeUIView(context: Context) -> PDFView {
        makePDFView(coordinator: context.coordinator)
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        updatePDFView(view, coordinator: context.coordinator)
    }
}
#endif

private extension PDFContainer {
    func makePDFView(coordinator: PDFViewCoordinator) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.document = PDFDocument(url: url)
        coordinator.observe(view)
        coordinator.addAnnotationGesture(to: view)
        updatePDFView(view, coordinator: coordinator)
        return view
    }

    func updatePDFView(_ view: PDFView, coordinator: PDFViewCoordinator) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            coordinator.renderedDocumentURL = nil
        }
        guard let pdfDocument = view.document else { return }

        if selection == nil, view.currentSelection != nil {
            view.clearSelection()
        }

        if pageCount != pdfDocument.pageCount {
            DispatchQueue.main.async { pageCount = pdfDocument.pageCount }
        }
        if pdfDocument.pageCount > 0,
           currentPage >= 0,
           currentPage < pdfDocument.pageCount,
           view.currentPage.map({ pdfDocument.index(for: $0) }) != currentPage,
           let page = pdfDocument.page(at: currentPage) {
            view.go(to: page)
        }

        let annotationSignature = annotations
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .map { "\($0.id.uuidString):\($0.kindRawValue):\($0.updatedAt.timeIntervalSinceReferenceDate)" }
            .joined(separator: "|")
        if coordinator.renderedDocumentURL != url
            || coordinator.renderedAnnotationSignature != annotationSignature {
            renderAnnotations(in: pdfDocument)
            coordinator.renderedDocumentURL = url
            coordinator.renderedAnnotationSignature = annotationSignature
        }
    }

    func renderAnnotations(in pdfDocument: PDFDocument) {
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.userName?.hasPrefix("foliage:") == true {
                page.removeAnnotation(annotation)
            }
        }

        for record in annotations {
            guard let page = pdfDocument.page(at: record.pageIndex) else { continue }
            let bounds = CGRect(
                x: record.boundsX,
                y: record.boundsY,
                width: record.boundsWidth,
                height: record.boundsHeight
            )
            let subtype: PDFAnnotationSubtype = record.kind == .underline ? .underline : .highlight
            let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
            annotation.userName = "foliage:\(record.id.uuidString)"
            annotation.contents = record.noteBody.isEmpty ? record.selectedText : record.noteBody
#if os(macOS)
            annotation.color = annotationColor(
                hex: record.colorHex,
                alpha: record.kind == .underline ? 0.95 : 0.45
            )
#else
            annotation.color = annotationColor(
                hex: record.colorHex,
                alpha: record.kind == .underline ? 0.95 : 0.45
            )
#endif
            page.addAnnotation(annotation)
        }
    }

#if os(macOS)
    func annotationColor(hex: String, alpha: CGFloat) -> NSColor {
        let components = colorComponents(hex: hex)
        return NSColor(red: components.red, green: components.green, blue: components.blue, alpha: alpha)
    }
#else
    func annotationColor(hex: String, alpha: CGFloat) -> UIColor {
        let components = colorComponents(hex: hex)
        return UIColor(red: components.red, green: components.green, blue: components.blue, alpha: alpha)
    }
#endif

    func colorComponents(hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return (1, 0.88, 0.32)
        }
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }
}

final class PDFViewCoordinator: NSObject {
    var parent: PDFContainer
    var renderedDocumentURL: URL?
    var renderedAnnotationSignature = ""
    private weak var pdfView: PDFView?
    private var observers: [NSObjectProtocol] = []

    init(parent: PDFContainer) {
        self.parent = parent
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func observe(_ view: PDFView) {
        pdfView = view
        observers.append(NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: view,
            queue: .main
        ) { [weak self] _ in
            self?.pageChanged()
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .PDFViewSelectionChanged,
            object: view,
            queue: .main
        ) { [weak self] _ in
            self?.selectionChanged()
        })
    }

    func addAnnotationGesture(to view: PDFView) {
#if os(macOS)
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(annotationClicked(_:)))
        recognizer.delaysPrimaryMouseButtonEvents = false
        recognizer.delegate = self
#else
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(annotationTapped(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
#endif
        view.addGestureRecognizer(recognizer)
    }

#if os(macOS)
    @objc private func annotationClicked(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended, let view = pdfView else { return }
        handleAnnotationTap(at: recognizer.location(in: view), in: view)
    }
#else
    @objc private func annotationTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let view = pdfView else { return }
        handleAnnotationTap(at: recognizer.location(in: view), in: view)
    }
#endif

    private func handleAnnotationTap(at location: CGPoint, in view: PDFView) {
        guard let document = view.document,
              let page = view.page(for: location, nearest: false) else {
            setAnnotationTap(nil)
            clearSelection(in: view)
            return
        }

        let pagePoint = view.convert(location, to: page)
        guard let annotation = page.annotations.reversed().first(where: {
            $0.userName?.hasPrefix("foliage:") == true && $0.bounds.contains(pagePoint)
        }),
        let userName = annotation.userName,
        let annotationID = UUID(uuidString: String(userName.dropFirst("foliage:".count))) else {
            setAnnotationTap(nil)
            if view.currentSelection?.bounds(for: page).contains(pagePoint) != true {
                clearSelection(in: view)
            }
            return
        }

#if os(macOS)
        let topY = view.isFlipped ? location.y : view.bounds.height - location.y
#else
        let topY = location.y
#endif
        setCurrentPage(document.index(for: page))
        setSelection(nil)
        setAnnotationTap(PDFAnnotationTap(
            annotationID: annotationID,
            actionAnchor: CGPoint(x: location.x, y: topY)
        ))
    }

    private func clearSelection(in view: PDFView) {
        view.clearSelection()
        setSelection(nil)
    }

    private func pageChanged() {
        guard let view = pdfView,
              let document = view.document,
              let page = view.currentPage else { return }
        setCurrentPage(document.index(for: page))
    }

    private func selectionChanged() {
        guard let view = pdfView,
              let document = view.document,
              let pdfSelection = view.currentSelection,
              let text = pdfSelection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              let page = pdfSelection.pages.first else {
            setSelection(nil)
            return
        }
        setSelection(PDFSelectionSnapshot(
            text: text,
            pageIndex: document.index(for: page),
            bounds: pdfSelection.bounds(for: page),
            actionAnchor: actionAnchor(for: pdfSelection, on: page, in: view)
        ))
    }

    private func actionAnchor(for selection: PDFSelection, on page: PDFPage, in view: PDFView) -> CGPoint {
        let convertedBounds = view.convert(selection.bounds(for: page), from: page)
#if os(macOS)
        let topEdge = view.isFlipped ? convertedBounds.minY : view.bounds.height - convertedBounds.maxY
#else
        let topEdge = convertedBounds.minY
#endif
        return CGPoint(x: convertedBounds.midX, y: topEdge)
    }

    private func setCurrentPage(_ page: Int) {
        parent.currentPage = page
    }

    private func setSelection(_ selection: PDFSelectionSnapshot?) {
        parent.selection = selection
    }

    private func setAnnotationTap(_ annotationTap: PDFAnnotationTap?) {
        parent.annotationTap = annotationTap
    }
}

#if os(macOS)
extension PDFViewCoordinator: NSGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif

#if os(iOS)
extension PDFViewCoordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
#endif

struct PDFPageThumbnail: View {
    let url: URL
    let pageIndex: Int

#if os(macOS)
    @State private var image: NSImage?
#else
    @State private var image: UIImage?
#endif

    var body: some View {
        ZStack {
            Color.white
            if let image {
#if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
#else
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
#endif
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: "\(url.path):\(pageIndex)") {
            guard let page = PDFDocument(url: url)?.page(at: pageIndex) else { return }
            image = page.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
        }
    }
}
#endif
