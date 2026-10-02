import SwiftUI
import VerbKit

/// What the app shows on a first run, before any verb data exists. It continues the
/// launch screen: the same image in the same place on the same navy, so the hand-off
/// does not move; the loading status or an error is layered on top.
struct DataLoadingView: View {
    let state: FirstLaunchState
    let onRetry: () -> Void

    /// The launch screen's background colour (LaunchBackground in the asset catalog).
    private let navy = Color(red: 0.043, green: 0.063, blue: 0.149)

    private var failure: VerbSyncError? {
        if case .failed(let error) = state { return error }
        return nil
    }

    var body: some View {
        ZStack {
            navy.ignoresSafeArea()

            Image("LaunchImage")
                .overlay(alignment: .bottom) {
                    if failure == nil { status }
                }
                // With an error, the artwork shrinks upward to make room for the card.
                .scaleEffect(failure == nil ? 1 : 0.6)
                .offset(y: failure == nil ? 0 : -110)

            if let failure {
                VStack {
                    Spacer()
                    errorCard(failure)
                }
                .padding(20)
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: failure != nil)
        // Light type and controls on the dark background, whatever the app's appearance.
        .environment(\.colorScheme, .dark)
    }

    private var status: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading verb data…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.bottom, 14)
    }

    private func errorCard(_ error: VerbSyncError) -> some View {
        let content = Self.content(for: error)
        return VStack(spacing: 14) {
            Image(systemName: content.symbol)
                .font(.system(size: 34))
                .foregroundStyle(.white)
            Text(content.title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(content.message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
            Button("Try Again", action: onRetry)
                .buttonStyle(.glassProminent)
        }
        .padding(24)
        .frame(maxWidth: 420)
        .glassEffect(in: RoundedRectangle(cornerRadius: 28))
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
