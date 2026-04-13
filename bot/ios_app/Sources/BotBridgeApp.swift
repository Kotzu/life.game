import SwiftUI
import ActivityKit

@main
struct BotBridgeApp: App {
    @StateObject private var botLoop = BotLoop()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(botLoop)
        }
    }
}
