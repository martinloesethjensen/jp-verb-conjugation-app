import SwiftUI
import VerbKit

/// A lesson's usages: numbered cards, each with its examples on genkō paper and the pattern
/// underlined. Usages at hidden levels stay behind a dashed Show row, for this visit only.
struct LessonUsages: View {
    let point: GrammarPoint

    @Environment(\.palette) private var palette
    @AppStorage(LevelSettings.defaultsKey, store: .appGroup) private var hiddenLevelsRaw = ""
    @State private var showingHidden = false

    private var levels: LevelSettings { LevelSettings(rawValue: hiddenLevelsRaw) }
    private var visible: [GrammarUsage] { point.visibleUsages(in: levels) }
    private var shown: [GrammarUsage] { showingHidden ? point.usages : visible }
    private var hiddenCount: Int { point.usages.count - visible.count }
    private var patterns: [String] { GrammarHighlight.patterns(of: point) }

    private var hiddenLevels: String {
        Set(point.usages.compactMap { point.level(of: $0) }).filter { !levels.isVisible($0) }
            .sorted().map(\.displayName).joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hiddenCount > 0 {
                SectionHeader("Usages") { Text("\(visible.count) of \(point.usages.count) at your levels") }
            } else {
                SectionHeader("Usages")
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { index, usage in
                usageCard(usage, number: index + 1)
            }
            if hiddenCount > 0 { hiddenRow }
        }
    }

    private func usageCard(_ usage: GrammarUsage, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(palette.onButton)
                    .frame(width: 26, height: 26)
                    .background(palette.button, in: Circle())
                    .accessibilityHidden(true)
                JapaneseText(usage.heading)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                if point.hasMixedLevels {
                    Spacer(minLength: 0)
                    LevelBadge(level: point.level(of: usage))
                }
            }
            JapaneseText(usage.explanation)
                .font(.subheadline)
                .foregroundStyle(palette.ink)
            if !usage.examples.isEmpty {
                ExampleList(examples: usage.examples, patterns: patterns)
            }
        }
        .paperCard(cornerRadius: 14)
    }

    private var hiddenRow: some View {
        HStack {
            Text(showingHidden ? "Usages at hidden levels are shown" :
                    (hiddenCount == 1 ? "1 usage at a hidden level (\(hiddenLevels))"
                                      : "\(hiddenCount) usages at a hidden level (\(hiddenLevels))"))
                .font(.subheadline)
                .foregroundStyle(palette.muted)
            Spacer(minLength: 8)
            Button(showingHidden ? "Hide" : "Show") {
                withAnimation { showingHidden.toggle() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(palette.button)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }
}

/// Examples on one genkō card, separated by hairlines, with the lesson's pattern underlined.
struct ExampleList: View {
    let examples: [GrammarExample]
    let patterns: [String]

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                if index > 0 { Divider().overlay(palette.rule) }
                ExampleRow(example: example, highlight: GrammarHighlight.range(in: example.jp, patterns: patterns))
                    .padding(.vertical, 8)
            }
        }
        .paperCard(cornerRadius: 12, ruled: true)
    }
}
