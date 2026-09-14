import SwiftUI

/// Shown when this device's sign-in attempt was rejected because the account
/// is already active on a different device (single-device enforcement).
struct DeviceConflictView: View {
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Already signed in on another device")
                .font(.headline)
            Text("This account can only be active on one device at a time. Sign out on the other device, then try again here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Back to sign in") {
                authService.acknowledgeDeviceConflict()
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
            Spacer()
        }
    }
}

#Preview {
    DeviceConflictView()
        .environmentObject(AuthService())
}
