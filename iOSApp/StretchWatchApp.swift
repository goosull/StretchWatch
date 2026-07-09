import SwiftUI

@main
struct StretchWatchApp: App {
    @StateObject private var sync = PhoneSync.shared

    init() { PhoneSync.shared.activate() }

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(sync)
        }
    }
}
