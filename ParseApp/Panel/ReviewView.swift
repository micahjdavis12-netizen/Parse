import SwiftUI
import ParseCore

struct ReviewView: View {
    @Bindable var session: SessionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if session.proposedChange?.usedCloud == true {
                    Text("Using cloud for this change")
                        .font(ParseTheme.captionFont)
                        .foregroundStyle(.secondary)
                }
                if let what = session.proposedChange?.whatChangedEnglish {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What changed")
                            .font(ParseTheme.captionFont)
                            .foregroundStyle(.secondary)
                        Text(what)
                            .font(ParseTheme.explanationFont)
                            .textSelection(.enabled)
                    }
                }
                if let flags = session.proposedChange?.safetyFlags, !flags.isEmpty {
                    SafetyBanner(flags: flags, acknowledged: session.safetyAcknowledged)
                }
                if let hunks = session.proposedChange?.hunks {
                    DiffView(hunks: hunks)
                }
            }
            .padding(10)
        }
    }
}

struct SafetyBanner: View {
    var flags: [SafetyFlag]
    var acknowledged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(acknowledged ? "You reviewed this risk. Insert will apply the change." : "This change may have side effects.", systemImage: "exclamationmark.triangle")
                .font(ParseTheme.captionFont)
                .foregroundStyle(.orange)
            ForEach(flags) { flag in
                VStack(alignment: .leading, spacing: 2) {
                    Text(flag.title)
                        .font(ParseTheme.headerFont)
                    Text(flag.consequence)
                        .font(ParseTheme.captionFont)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: ParseTheme.controlRadius, style: .continuous))
    }
}

struct DiffView: View {
    var hunks: [DiffLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current → Proposed")
                .font(ParseTheme.captionFont)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(hunks) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(gutter(line))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 14, alignment: .center)
                        Text(lineNumber(line))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 28, alignment: .trailing)
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(ParseTheme.monoFont)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 1)
                    .padding(.horizontal, 8)
                    .background(background(line.kind))
                }
            }
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: ParseTheme.controlRadius, style: .continuous))
        }
    }

    private func gutter(_ line: DiffLine) -> String {
        switch line.kind {
        case .insert: "+"
        case .delete: "−"
        case .equal: " "
        }
    }

    private func lineNumber(_ line: DiffLine) -> String {
        if let newLine = line.newLine { return "\(newLine)" }
        if let oldLine = line.oldLine { return "\(oldLine)" }
        return ""
    }

    private func background(_ kind: DiffKind) -> Color {
        switch kind {
        case .insert: ParseTheme.insertGreen
        case .delete: ParseTheme.deleteRed
        case .equal: .clear
        }
    }
}
