import SwiftUI
import VerbKit

struct DataLoadingView: View {
    let state: FirstLaunchState
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            switch state {
            case .checking, .fetching:
                ProgressView()
                Text("Loading verb data…")
                    .font(.headline)

            case .failed(.offline):
                Image(systemName: "wifi.slash")
                    .font(.system(size: 48))
                Text("No Internet Connection")
                    .font(.headline)
                Text("JP Verb Conjugation needs to download verb data the first time it runs. Connect to the internet and try again.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)

            case .failed(.serverUnreachable):
                Image(systemName: "exclamationmark.icloud")
                    .font(.system(size: 48))
                Text("Can't Reach the Server")
                    .font(.headline)
                Text("Your device is online, but the verb data couldn't be downloaded. This is usually temporary — try again in a moment.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)

            case .failed(.malformedData):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                Text("Something Went Wrong")
                    .font(.headline)
                Text("The downloaded verb data couldn't be read. Please try again.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.borderedProminent)

            case .success:
                ProgressView()
            }
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}
