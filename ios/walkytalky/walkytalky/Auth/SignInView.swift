import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("walkytalky")
                .font(.largeTitle.bold())
            Text("Chat securely, anonymously.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    isSigningIn = true
                    await authService.signInAnonymously()
                    isSigningIn = false
                }
            } label: {
                if isSigningIn {
                    ProgressView()
                } else {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn)
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()
        }
        .alert("Sign-in error", isPresented: errorBinding) {
            Button("OK") { authService.lastErrorMessage = nil }
        } message: {
            Text(authService.lastErrorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { authService.lastErrorMessage != nil },
            set: { if !$0 { authService.lastErrorMessage = nil } }
        )
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthService())
}
