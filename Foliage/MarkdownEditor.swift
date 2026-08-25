import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MarkdownEditor: View {
    @Binding var text: String
    let placeholder: String
    let minHeight: CGFloat

    @AppStorage("noteEditorFontSize") private var fontSize = 18.0
    @FocusState private var isEditorFocused: Bool
    @State private var isEditing: Bool
#if os(macOS)
    @State private var outsideClickMonitor: Any?
#endif

    init(text: Binding<String>, placeholder: String, minHeight: CGFloat) {
        _text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
        _isEditing = State(initialValue: text.wrappedValue.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("Markdown + Math", systemImage: "text.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Smaller") { fontSize = max(14, fontSize - 1) }
                    Button("Larger") { fontSize = min(28, fontSize + 1) }
                    Divider()
                    Button("Default (18 pt)") { fontSize = 18 }
                } label: {
                    Label("Font size \(Int(fontSize))", systemImage: "textformat.size")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.borderlessButton)
                .help("Note font size: \(Int(fontSize)) pt")
                Text(isEditing ? "Editing" : "Tap to edit")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Group {
                if isEditing {
                    TextEditor(text: $text)
                        .font(.system(size: fontSize))
                        .focused($isEditorFocused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: minHeight)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholder)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginEditing)
                } else {
                    MathMarkdownView(text, fontSize: fontSize)
                        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginEditing)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        }
        .onChange(of: isEditorFocused) {
#if os(macOS)
            if isEditorFocused {
                startMonitoringOutsideClicks()
            } else {
                stopMonitoringOutsideClicks()
            }
#endif
            if !isEditorFocused {
                isEditing = false
            }
        }
#if os(macOS)
        .onDisappear(perform: stopMonitoringOutsideClicks)
#endif
    }

    private func beginEditing() {
        isEditing = true
        Task { @MainActor in
            isEditorFocused = true
        }
    }

#if os(macOS)
    private func startMonitoringOutsideClicks() {
        stopMonitoringOutsideClicks()
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window,
                  let textView = window.firstResponder as? NSTextView,
                  let clickedView = window.contentView?.hitTest(event.locationInWindow) else {
                return event
            }

            let editorRoot = textView.enclosingScrollView ?? textView
            guard clickedView !== editorRoot, !clickedView.isDescendant(of: editorRoot) else {
                return event
            }

            DispatchQueue.main.async {
                isEditorFocused = false
                isEditing = false
            }
            return event
        }
    }

    private func stopMonitoringOutsideClicks() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }
#endif
}
