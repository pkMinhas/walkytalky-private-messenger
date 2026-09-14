import SwiftUI

/// Six dots reflecting how many digits have been typed, backed by an
/// invisible numeric text field so the system keyboard drives entry.
struct PasscodeEntryView: View {
    @Binding var digits: String
    var isDisabled: Bool = false

    private let length = 6
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 16) {
                ForEach(0..<length, id: \.self) { index in
                    Circle()
                        .fill(index < digits.count ? Color.primary : Color.clear)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1))
                }
            }

            TextField("", text: $digits)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0.01)
                .disabled(isDisabled)
                .onChange(of: digits) { _, newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(length))
                    if filtered != newValue {
                        digits = filtered
                    }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isDisabled { isFocused = true } }
        .onAppear { if !isDisabled { isFocused = true } }
        .onChange(of: isDisabled) { _, disabled in
            if disabled { isFocused = false }
        }
    }
}
