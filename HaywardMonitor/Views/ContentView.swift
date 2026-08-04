import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        switch model.phase {
        case .loggedOut:
            LoginView()
        case .connecting:
            ProgressView("Connexion au cloud Hayward…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            DashboardView()
        }
    }
}
