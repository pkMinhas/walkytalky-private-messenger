import SwiftUI

/// Verify the current passcode, then set a new one. Reuses `PasscodeService.verify`
/// for the current-passcode check, so a wrong guess here still counts toward
/// the same exponential lockout as the lock screen.
struct ChangePasscodeView: View {
    @EnvironmentObject private var passcodeService: PasscodeService
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .verifyCurrent
    @State private var digits = ""
    @State private var firstNewEntry = ""
    @State private var errorMessage: String?

    private enum Step {
        case verifyCurrent, enterNew, confirmNew
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(title)
                .font(.headline)
            PasscodeEntryView(digits: $digits, isDisabled: passcodeService.isLockedOut)
                .frame(height: 44)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if passcodeService.isLockedOut {
                Text("Too many attempts. Try again shortly.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Change Passcode")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: digits) { _, newValue in
            guard newValue.count == 6 else { return }
            switch step {
            case .verifyCurrent:
                if passcodeService.verify(newValue) {
                    errorMessage = nil
                    step = .enterNew
                } else {
                    errorMessage = "Incorrect passcode"
                }
                digits = ""
            case .enterNew:
                firstNewEntry = newValue
                digits = ""
                errorMessage = nil
                step = .confirmNew
            case .confirmNew:
                if newValue == firstNewEntry {
                    passcodeService.setPasscode(newValue)
                    dismiss()
                } else {
                    errorMessage = "Passcodes didn't match. Try again."
                    digits = ""
                    step = .enterNew
                }
            }
        }
    }

    private var title: String {
        switch step {
        case .verifyCurrent: "Enter current passcode"
        case .enterNew: "Enter new passcode"
        case .confirmNew: "Confirm new passcode"
        }
    }
}

#Preview {
    NavigationStack {
        ChangePasscodeView()
    }
    .environmentObject(PasscodeService())
}
