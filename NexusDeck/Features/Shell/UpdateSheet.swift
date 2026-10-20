import SwiftUI

/// "Update available" window: release notes (formatted like on GitHub) and the download & install button.
struct UpdateSheet: View {
    @ObservedObject var updater = Updater.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("È disponibile NexusDeck \(updater.latestVersion ?? updater.installingVersion ?? "")")
                        .font(.system(size: 17, weight: .bold))
                    Text("Versione installata: \(Updater.currentVersion)").font(.system(size: 12)).foregroundStyle(Theme.textMid)
                }
                Spacer()
            }
            .padding(22)
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1)
            ScrollView {
                MarkdownView(text: updater.notes.isEmpty ? "Nessuna nota per questa versione." : updater.notes)
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1)
            HStack(spacing: 12) {
                switch updater.state {
                case .downloading:
                    ProgressView().controlSize(.small); Text("Download in corso…").foregroundStyle(Theme.textMid)
                case .installing:
                    ProgressView().controlSize(.small); Text("Installazione… NexusDeck si riavvierà da solo.").foregroundStyle(Theme.textMid)
                case .failed(let e):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(e).foregroundStyle(Theme.textMid).lineLimit(2)
                default:
                    EmptyView()
                }
                Spacer()
                FlatButton(title: "Più tardi", width: 110) { dismiss() }
                    .disabled(updater.isBusy)
                FlatButton(title: "Scarica e installa", width: 170) { Task { await updater.install() } }
                    .disabled(updater.isBusy || updater.latestVersion == nil)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 18).frame(height: 64)
            .background(Theme.settingsFooter)
        }
        .frame(width: 620, height: 560)
        .background(Theme.settingsBg)
        .foregroundStyle(Theme.text)
        
    }
}

/// Minimal GitHub-style Markdown: headings, bullet lists (nested), numbered lists, code blocks, paragraphs,
/// and inline bold / italic / code / links.
struct MarkdownView: View {
    let text: String

    private enum Block: Hashable {
        case heading(Int, String), bullet(Int, String), numbered(Int, String, String), code(String), paragraph(String), rule
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var code: [String]?
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: " "))); para = [] } }
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let c = code { out.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(line); continue }
            let indent = (line.prefix { $0 == " " }.count) / 2
            if trimmed.isEmpty { flush(); continue }
            if trimmed == "---" || trimmed == "***" { flush(); out.append(.rule); continue }
            if let h = trimmed.firstIndex(where: { $0 != "#" }), trimmed.hasPrefix("#"), trimmed[h] == " " {
                flush(); out.append(.heading(trimmed.distance(from: trimmed.startIndex, to: h), String(trimmed[h...]).trimmingCharacters(in: .whitespaces))); continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flush(); out.append(.bullet(indent, String(trimmed.dropFirst(2)))); continue
            }
            if let dot = trimmed.firstIndex(of: "."), trimmed[..<dot].allSatisfy(\.isNumber), !trimmed[..<dot].isEmpty,
               trimmed.index(after: dot) < trimmed.endIndex, trimmed[trimmed.index(after: dot)] == " " {
                flush(); out.append(.numbered(indent, String(trimmed[..<dot]), String(trimmed[trimmed.index(dot, offsetBy: 2)...]))); continue
            }
            para.append(trimmed)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flush()
        return out
    }

    private func inline(_ s: String) -> AttributedString {
        var a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].font = .system(size: 12, design: .monospaced)
            a[run.range].backgroundColor = Color.white.opacity(0.08)
        }
        return a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b {
                case .heading(let level, let t):
                    Text(inline(t)).font(.system(size: level <= 1 ? 20 : level == 2 ? 17 : 14.5, weight: .bold))
                        .padding(.top, level <= 2 ? 6 : 4)
                    if level <= 2 { Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 1) }
                case .bullet(let indent, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(indent == 0 ? "•" : "◦").foregroundStyle(Theme.accent)
                        Text(inline(t)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(indent) * 18)
                case .numbered(let indent, let n, let t):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(n).").foregroundStyle(Theme.accent).monospacedDigit()
                        Text(inline(t)).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(indent) * 18)
                case .code(let t):
                    Text(t).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 6))
                case .paragraph(let t):
                    Text(inline(t)).fixedSize(horizontal: false, vertical: true)
                case .rule:
                    Rectangle().fill(Theme.separator).frame(height: 1).padding(.vertical, 4)
                }
            }
        }
        .font(.system(size: 13))
        .tint(Theme.accent)
        .textSelection(.enabled)
    }
}
