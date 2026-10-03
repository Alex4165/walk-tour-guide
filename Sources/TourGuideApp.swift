import SwiftUI

@main
struct TourGuideApp: App {
    @State private var walk = Walk()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Text(walk.status)
                    .multilineTextAlignment(.center)
                Button(walk.isRunning ? "Stop walk" : "Start walk") {
                    if walk.isRunning {
                        walk.stop()
                    } else {
                        Task { await walk.start() }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
