import SwiftUI
import VerbKit

/// The playground: step from 1 to 10 (or 何), see that many objects, and read the counted form
/// large. A number whose reading changes gets the same tint and dot as the grid below.
struct CountThemCard: View {
    let counter: Counter
    @Binding var number: CounterNumber
    @State private var thing: CountedThing?
    @State private var lastCount = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var things: [CountedThing] { counter.thingsByFit }
    private var count: Int? {
        if case let .n(value) = number { return value }
        return nil
    }
    private var readings: [String] { counter.readings(for: number) }
    private var preferred: String { readings.first ?? "" }
    private var changed: Bool { counter.isChanged(number) }
    private var symbol: String { thing?.symbol ?? counter.symbol }
    private var animation: Animation? { reduceMotion ? nil : .snappy }

    var body: some View {
        VStack(spacing: 12) {
            objects
            reading
            controls
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            if thing == nil { thing = things.first }
            if let count { lastCount = count }
        }
    }

    // MARK: objects

    private var objects: some View {
        Group {
            if let count {
                ChipFlowLayout(spacing: 6) {
                    ForEach(0..<count, id: \.self) { _ in
                        Image(systemName: symbol)
                            .font(.title)
                            .foregroundStyle(.tint)
                            .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                    }
                }
            } else {
                Image(systemName: "questionmark.circle")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .animation(animation, value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(objectsLabel)
    }

    private var objectsLabel: String {
        guard let count else { return "How many?" }
        let meaning = thing?.meaning ?? counter.meaning
        let plural = count == 1 || meaning.contains("(") ? meaning : meaning + "s"
        return "\(count) \(plural)"
    }

    // MARK: reading

    private var reading: some View {
        VStack(spacing: 4) {
            Text(counter.written(number))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(preferred)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(reduceMotion ? .identity : .numericText())
            if let thing {
                Text("\(thing.word)を\(counter.written(number))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(changed ? Color.orange.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if changed {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .speakOnTap(preferred)
        .textActions(preferred)
        .animation(animation, value: number)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(counter.written(number)), \(preferred)\(changed ? ", sound changes" : "")")
        .accessibilityHint("Speaks the reading")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: controls

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                step(-1)
            } label: {
                Image(systemName: "minus").frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .disabled(count == 1)
            .accessibilityLabel("One fewer")

            Text(count.map(String.init) ?? "何")
                .font(.title3.weight(.semibold))
                .frame(minWidth: 32)
                .accessibilityHidden(true)

            Button {
                step(1)
            } label: {
                Image(systemName: "plus").frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .disabled(count == 10 || count == nil)
            .accessibilityLabel("One more")

            whatButton

            if things.count > 1 {
                Menu {
                    Picker("Thing", selection: $thing) {
                        ForEach(things) { option in
                            Text("\(option.word)  \(option.meaning)").tag(Optional(option))
                        }
                    }
                } label: {
                    Image(systemName: symbol).frame(width: 36, height: 36)
                }
                .buttonStyle(.glass)
                .accessibilityLabel("Thing to count: \(thing?.meaning ?? "")")
            }
        }
    }

    private var whatLabel: some View {
        Text("何")
            .font(.body.weight(.semibold))
            .padding(.horizontal, 6)
            .frame(height: 36)
    }

    /// The 何 chip: selected while the playground asks "how many?".
    @ViewBuilder private var whatButton: some View {
        if number == .what {
            Button(action: toggleWhat) { whatLabel }
                .buttonStyle(.glassProminent)
                .accessibilityLabel("How many")
                .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: toggleWhat) { whatLabel }
                .buttonStyle(.glass)
                .accessibilityLabel("How many")
        }
    }

    private func step(_ delta: Int) {
        let next = min(10, max(1, (count ?? lastCount) + delta))
        lastCount = next
        withAnimation(animation) { number = .n(next) }
    }

    private func toggleWhat() {
        withAnimation(animation) {
            number = number == .what ? .n(lastCount) : .what
        }
    }
}
