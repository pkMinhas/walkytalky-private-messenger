import SwiftUI

/// Shown once, right after first sign-in, to establish the local passcode.
struct PasscodeSetupView: View {
    @EnvironmentObject private var passcodeService: PasscodeService
    @State private var step: Step = .enter
    @State private var firstEntry = ""
    @State private var digits = ""
    @State private var errorMessage: String?

    private enum Step {
        case enter, confirm
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock")
                .font(.system(size: 40))
            Text(step == .enter ? "Create a passcode" : "Confirm your passcode")
                .font(.headline)
            PasscodeEntryView(digits: $digits)
                .frame(height: 44)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
        .onChange(of: digits) { _, newValue in
            guard newValue.count == 6 else { return }
            switch step {
            case .enter:
                firstEntry = newValue
                digits = ""
                errorMessage = nil
                step = .confirm
            case .confirm:
                if newValue == firstEntry {
                    let candidate = newValue
                    Task {
                        await passcodeService.setPasscode(candidate)
                    }
                } else {
                    errorMessage = "Passcodes didn't match. Try again."
                    firstEntry = ""
                    digits = ""
                    step = .enter
                }
            }
        }
    }
}

#Preview {
    PasscodeSetupView()
        .environmentObject(PasscodeService())
}
