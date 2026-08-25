import SwaTex
import SwaTexRender
import SwiftUI

struct MathMarkdownView: View {
    private let source: String
    private let maximumSourceLines: Int?
    private let fontSize: CGFloat

    init(_ source: String, maximumSourceLines: Int? = nil, fontSize: CGFloat = 17) {
        self.source = source
        self.maximumSourceLines = maximumSourceLines
        self.fontSize = fontSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .markdown(let markdown):
                    InlineMathText(markdown, fontSize: fontSize)
                        .fixedSize(horizontal: false, vertical: true)
                case .displayMath(let formula):
                    ScrollView(.horizontal) {
                        MathView(formula)
                            .font(size: fontSize + 2)
                            .mathColor(SwiftUI.Color.primary)
                            .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blocks: [MathMarkdownBlock] {
        let limitedSource: String
        if let maximumSourceLines {
            limitedSource = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .prefix(maximumSourceLines)
                .joined(separator: "\n")
        } else {
            limitedSource = source
        }
        return MathMarkdownParser.blocks(in: limitedSource)
    }
}

private struct InlineMathText: View {
    @Environment(\.colorScheme) private var colorScheme

    let source: String
    let fontSize: CGFloat

    init(_ source: String, fontSize: CGFloat) {
        self.source = source
        self.fontSize = fontSize
    }

    var body: some View {
        composedText
            .font(.system(size: fontSize))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composedText: Text {
        MathMarkdownParser.inlineSegments(in: source).reduce(Text("")) { result, segment in
            switch segment {
            case .markdown(let markdown):
                return Text("\(result)\(Text(renderedMarkdown(markdown)))")
            case .math(let formula):
                return Text("\(result)\(renderedMath(formula))")
            }
        }
    }

    private func renderedMarkdown(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }

    private func renderedMath(_ formula: String) -> Text {
        let mathColor = colorScheme == .dark
            ? SwaTex.Color(r: 1, g: 1, b: 1, a: 1)
            : SwaTex.Color(r: 0, g: 0, b: 0, a: 1)
        let image = try? ImageRenderer.image(
            latex: formula,
            style: .text,
            color: mathColor,
            options: RenderOptions(fontSize: fontSize, padding: 0),
            displayScale: 2
        )

        guard let image else {
            return Text("$\(formula)$").foregroundColor(.red)
        }

        return Text(Image(decorative: image, scale: 2, orientation: .up))
            .baselineOffset(-2)
    }
}

private enum MathMarkdownBlock {
    case markdown(String)
    case displayMath(String)
}

private enum InlineMathSegment {
    case markdown(String)
    case math(String)
}

private enum MathMarkdownParser {
    static func blocks(in source: String) -> [MathMarkdownBlock] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MathMarkdownBlock] = []
        var markdownLines: [String] = []
        var displayLines: [String] = []
        var isInsideDisplayMath = false

        func appendMarkdown() {
            guard !markdownLines.isEmpty else { return }
            blocks.append(.markdown(markdownLines.joined(separator: "\n")))
            markdownLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isInsideDisplayMath {
                if let closingRange = trimmed.range(of: "$$") {
                    displayLines.append(String(trimmed[..<closingRange.lowerBound]))
                    blocks.append(.displayMath(displayLines.joined(separator: "\n")))
                    displayLines.removeAll(keepingCapacity: true)
                    isInsideDisplayMath = false

                    let remainder = trimmed[closingRange.upperBound...]
                    if !remainder.isEmpty {
                        markdownLines.append(String(remainder))
                    }
                } else {
                    displayLines.append(line)
                }
                continue
            }

            guard trimmed.hasPrefix("$$") else {
                markdownLines.append(line)
                continue
            }

            appendMarkdown()
            let formulaStart = trimmed.index(trimmed.startIndex, offsetBy: 2)
            let remainder = trimmed[formulaStart...]
            if let closingRange = remainder.range(of: "$$") {
                blocks.append(.displayMath(String(remainder[..<closingRange.lowerBound])))
                let trailingText = remainder[closingRange.upperBound...]
                if !trailingText.isEmpty {
                    markdownLines.append(String(trailingText))
                }
            } else {
                displayLines.append(String(remainder))
                isInsideDisplayMath = true
            }
        }

        if isInsideDisplayMath {
            blocks.append(.displayMath(displayLines.joined(separator: "\n")))
        }
        appendMarkdown()
        return blocks.isEmpty ? [.markdown("")] : blocks
    }

    static func inlineSegments(in source: String) -> [InlineMathSegment] {
        var segments: [InlineMathSegment] = []
        var markdownStart = source.startIndex
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "\\" {
                index = source.index(after: index)
                if index < source.endIndex {
                    index = source.index(after: index)
                }
                continue
            }

            guard source[index] == "$" else {
                index = source.index(after: index)
                continue
            }

            let formulaStart = source.index(after: index)
            guard formulaStart < source.endIndex, source[formulaStart] != "$",
                  let formulaEnd = closingDollar(in: source, after: formulaStart) else {
                index = formulaStart
                continue
            }

            if markdownStart < index {
                segments.append(.markdown(String(source[markdownStart..<index])))
            }
            segments.append(.math(String(source[formulaStart..<formulaEnd])))
            index = source.index(after: formulaEnd)
            markdownStart = index
        }

        if markdownStart < source.endIndex {
            segments.append(.markdown(String(source[markdownStart...])))
        }
        return segments.isEmpty ? [.markdown(source)] : segments
    }

    private static func closingDollar(in source: String, after start: String.Index) -> String.Index? {
        var index = start
        while index < source.endIndex {
            if source[index] == "\\" {
                index = source.index(after: index)
                if index < source.endIndex {
                    index = source.index(after: index)
                }
                continue
            }
            if source[index] == "$" {
                return index
            }
            index = source.index(after: index)
        }
        return nil
    }
}
