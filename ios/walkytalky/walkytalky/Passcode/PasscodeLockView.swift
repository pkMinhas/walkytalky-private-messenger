import SwiftUI

/// Shown on cold start and whenever the app returns to the foreground after
/// the auto-lock timeout has elapsed.
struct PasscodeLockView: View {
    @EnvironmentObject private var passcodeService: PasscodeService
    @State private var digits = ""
    @State private var showIncorrect = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
            Text("Enter passcode")
                .font(.headline)
            PasscodeEntryView(digits: $digits, isDisabled: passcodeService.isLockedOut)
                .frame(height: 44)

            if passcodeService.isLockedOut {
                Text("Too many attempts. Try again in \(countdownText).")
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if showIncorrect {
                Text("Incorrect passcode")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
        .onChange(of: digits) { _, newValue in
            guard newValue.count == 6 else { return }
            let success = passcodeService.verify(newValue)
            showIncorrect = !success
            digits = ""
        }
    }

    private var countdownText: String {
        let seconds = Int(passcodeService.lockoutRemaining.rounded(.up))
        let minutes = seconds / 60
        let remainder = seconds % 60
        return minutes > 0 ? String(format: "%d:%02d", minutes, remainder) : "\(seconds)s"
    }
}

#Preview {
    PasscodeLockView()
        .environmentObject(PasscodeService())
}
