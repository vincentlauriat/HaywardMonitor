import SwiftUI

@main
struct HaywardMonitorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 560)
                .onAppear { model.onLaunch() }
        }
    }
}
