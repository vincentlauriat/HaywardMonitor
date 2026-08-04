import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var model: AppModel
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.pool.swim")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Hayward Monitor")
                .font(.largeTitle.bold())

            Text("Connectez-vous avec votre compte PoolWatch / Vistapool.")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                SecureField("Mot de passe", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
                    .onSubmit(submit)
            }
            .frame(maxWidth: 320)

            if let error = model.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button(action: submit) {
                Text("Se connecter")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.isEmpty || password.isEmpty)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task { await model.signIn(email: email, password: password) }
    }
}
