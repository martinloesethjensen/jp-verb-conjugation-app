import SwiftUI
import VerbKit

enum OnboardingStep: Int, CaseIterable {
    case welcome, levels, furigana, theme, firstVerb
}

/// The first-run flow (shown once on a new install, `OnboardingProgress`): what the app is, the
/// levels studied, furigana, a theme, and a first verb. Finishing writes the choices and opens the
/// app, or 食べる's page.
struct OnboardingView: View {
    let firstVerb: Verb?
    let datasets: [Set<JLPTLevel>]
    let onFinish: (Route?) -> Void

    @State private var step: OnboardingStep = .welcome
    /// Seeded with the stored theme, which the theme page writes live, so a flow reopened after a
    /// kill rings the theme it is painted in and finishing keeps it.
    @State private var choices = OnboardingChoices(theme: ThemeChoice.load(from: .appGroup).theme)
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                page
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .id(step)
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .background(palette.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { primaryButton }
        .animation(reduceMotion ? nil : .smooth, value: step)
    }

    private var topBar: some View {
        HStack {
            Button("Back") { go(-1) }
                .foregroundStyle(palette.ink)
                .opacity(step == .welcome ? 0 : 1)
                .disabled(step == .welcome)
            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? palette.ink : palette.rule)
                        .frame(width: item == step ? 22 : 6, height: 6)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
            Spacer()
            Text("Back").opacity(0).accessibilityHidden(true)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: WelcomePage()
        case .levels: LevelsPage(choices: $choices)
        case .furigana: FuriganaPage(choices: $choices)
        case .theme: ThemePage(choices: $choices)
        case .firstVerb:
            FirstVerbPage(choices: choices, firstVerb: firstVerb, datasets: datasets) {
                finish(opening: firstVerb.map { .verb($0.id) })
            }
        }
    }

    private var primaryButton: some View {
        Button(step == .welcome ? "Get started" : step == .firstVerb ? "Open Verb Table" : "Continue") {
            if step == .firstVerb { finish(opening: nil) } else { go(1) }
        }
        .buttonStyle(.paper)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
    }

    private func go(_ delta: Int) {
        if let next = OnboardingStep(rawValue: step.rawValue + delta) { step = next }
    }

    private func finish(opening route: Route?) {
        choices.apply(to: .appGroup, amongEach: datasets)
        OnboardingProgress.finish(appGroup: .appGroup)
        onFinish(route)
    }
}

#Preview("Onboarding") {
    OnboardingView(firstVerb: nil, datasets: [[.n5, .n4]]) { _ in }
        .themedRoot()
}
