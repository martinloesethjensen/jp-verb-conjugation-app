import SwiftUI
import VerbKit

@main
struct JPVerbConjugationApp: App {
    var body: some Scene {
        WindowGroup {
            Text(verbKitPlaceholder ? "JP Verb Conjugation" : "")
                .padding()
        }
    }
}
