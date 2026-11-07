import SwiftUI
import VerbKit

/// What the app shows on a first run, before any verb data exists. It continues the first
/// frame: the theme's paper with its 活 seal at the launch image's exact size and place, so the
/// hand-off doesn't move; the loading status sits under the seal, and an error card below it.
struct DataLoadingView: View {
    let state: FirstLaunchState
    let onRetry: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    private var failure: VerbSyncError? {
        if case .failed(let error) = state { return error }
        return nil
    }

    private var stamp: ThemeStamp {
        let choice = ThemeChoice.load(from: .appGroup)
        return .stamp(for: choice.effectiveTheme(on: .now), isDark: colorScheme == .dark)
    }

    var body: some View {
        ZStack {
            palette.paper.ignoresSafeArea()

            SealView(stamp: stamp, ink: palette.ink)
                // With an error, the seal moves up to make room for the card.
                .offset(y: failure == nil ? 0 : -110)

            if failure == nil {
                status.offset(y: SealView.side / 2 + 28)
            } else if let failure {
                VStack {
                    Spacer()
                    errorCard(failure)
                }
                .padding(20)
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: failure != nil)
    }

    private var status: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading verb data…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.muted)
        }
    }

    private func errorCard(_ error: VerbSyncError) -> some View {
        let content = Self.content(for: error)
        return VStack(spacing: 14) {
            Image(systemName: content.symbol)
                .font(.system(size: 34))
                .foregroundStyle(palette.ink)
            Text(content.title)
                .font(.headline)
                .foregroundStyle(palette.ink)
            Text(content.message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.muted)
            Button("Try Again", action: onRetry)
                .buttonStyle(.paper)
        }
        .padding(12)
        .frame(maxWidth: 420)
        .paperCard(cornerRadius: 20, fillsWidth: false)
    }

    private static func content(for error: VerbSyncError) -> (symbol: String, title: String, message: String) {
        switch error {
        case .offline:
            return (
                "wifi.slash", "No Internet Connection",
                "JP Verb Conjugation needs to download verb data the first time it runs. Connect to the internet and try again."
            )
        case .serverUnreachable:
            return (
                "exclamationmark.icloud", "Can't Reach the Server",
                "Your device is online, but the verb data couldn't be downloaded. This is usually temporary — try again in a moment."
            )
        case .malformedData:
            return (
                "exclamationmark.triangle", "Something Went Wrong",
                "The downloaded verb data couldn't be read. Please try again."
            )
        case .untrusted:
            return (
                "lock.trianglebadge.exclamationmark", "Couldn't Verify the Data",
                "The downloaded verb data couldn't be verified, so it wasn't used. Please try again later."
            )
        }
    }
}
