import SwiftUI
import VerbKit

struct GrammarDetailView: View {
    let point: GrammarPoint
    @Environment(VerbStore.self) private var verbStore
    @Environment(\.openRoute) private var openRoute

    private let registerOrder: [GrammarRegister] = [.polite, .casual, .formal]

    /// Related points that exist locally; a link to a lesson that hasn't
    /// synced is hidden rather than dead.
    private var relatedPoints: [GrammarPoint] {
        point.related.compactMap { id in
            if case let .grammar(related)? = Route.grammar(id).resolve(verbs: [], grammarPoints: verbStore.grammarPoints) {
                return related
            }
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if !point.attachment.isEmpty { attachmentSection }
                usagesSection
                if !point.conjugations.isEmpty { conjugationsSection }
                if !point.pitfalls.isEmpty { pitfallsSection }
                if !relatedPoints.isEmpty { relatedSection }
            }
            .padding()
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(point.title)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                ReportProblemButton(item: "Lesson: \(point.title) (\(point.id))")
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let level = point.jlpt {
                Text(level.displayName)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .glassEffect(in: Capsule())
            }
            JapaneseText(point.title)
                .font(.largeTitle.weight(.heavy))
            JapaneseText(point.summary)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String? = nil) -> some View {
        Label {
            Text(title)
        } icon: {
            if let systemImage { Image(systemName: systemImage) }
        }
        .font(.title3.weight(.semibold))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: How it attaches

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("How it attaches")
            ForEach(Array(point.attachment.enumerated()), id: \.offset) { _, rule in
                card {
                    HStack(spacing: 6) {
                        Text(rule.wordClass.displayName).font(.subheadline.weight(.semibold))
                        if let condition = rule.condition {
                            JapaneseText("· \(condition)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    JapaneseText(rule.pattern).font(.headline)
                    // Examples are " / "-separated; one per line so long
                    // strings never wrap mid-word.
                    ForEach(rule.example.components(separatedBy: " / "), id: \.self) { example in
                        JapaneseText(example).font(.title3)
                    }
                    if let note = rule.note {
                        JapaneseText(note).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Usages

    private var usagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Usages")
            ForEach(Array(point.usages.enumerated()), id: \.offset) { index, usage in
                card {
                    JapaneseText("\(index + 1). \(usage.heading)").font(.headline)
                    JapaneseText(usage.explanation).font(.subheadline)
                    ForEach(Array(usage.examples.enumerated()), id: \.offset) { _, example in
                        Divider()
                        ExampleRow(example: example)
                    }
                }
            }
        }
    }

    // MARK: Conjugations

    private var conjugationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Conjugations")
            ForEach(registerOrder, id: \.self) { register in
                let forms = point.conjugations.filter { $0.register == register }
                if !forms.isEmpty {
                    card {
                        Text(register.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(Array(forms.enumerated()), id: \.offset) { _, conjugation in
                            VStack(alignment: .leading, spacing: 2) {
                                JapaneseText(conjugation.form).font(.headline)
                                if let note = conjugation.note {
                                    JapaneseText(note).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Watch out

    private var pitfallsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Watch out", systemImage: "exclamationmark.triangle")
            ForEach(Array(point.pitfalls.enumerated()), id: \.offset) { _, pitfall in
                card {
                    JapaneseText(pitfall.heading).font(.headline)
                    JapaneseText(pitfall.explanation).font(.subheadline)
                    ForEach(Array(pitfall.examples.enumerated()), id: \.offset) { _, example in
                        Divider()
                        ExampleRow(example: example)
                    }
                }
            }
        }
    }

    // MARK: Related

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Related")
            ForEach(relatedPoints) { related in
                Button {
                    openRoute(.grammar(related.id))
                } label: {
                    Label {
                        JapaneseText(related.title)
                    } icon: {
                        Image(systemName: "arrow.right.circle")
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }
}
