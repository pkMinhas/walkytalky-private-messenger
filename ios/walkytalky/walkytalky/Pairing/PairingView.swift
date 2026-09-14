import SwiftUI

/// Shows this device's QR code and offers scanning the peer's, then derives
/// and stores the conversation key. Doubles as the re-pair flow: each run
/// targets `currentVersion + 1`, so pairing again always bumps the key
/// version and discards the previous one (`ConversationKeyStore.store`).
struct PairingView: View {
    let conversation: Conversation

    @Environment(\.dismiss) private var dismiss
    @State private var showScanner = false
    @State private var errorMessage: String?
    @State private var didPair = false

    private var conversationId: String { conversation.id ?? "" }

    private var nextVersion: Int {
        (ConversationKeyStore.currentVersion(conversationId: conversationId) ?? 0) + 1
    }

    private var myPayload: PairingPayload {
        PairingPayload(conversationId: conversationId, publicKey: CryptoIdentity.publicKeyData)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if didPair {
                    pairedConfirmation
                } else {
                    pairingPrompt
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Pair Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ZStack(alignment: .topTrailing) {
                    QRScannerView { scanned in
                        showScanner = false
                        handleScan(scanned)
                    }
                    Button {
                        showScanner = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                    .padding()
                }
            }
        }
    }

    private var pairingPrompt: some View {
        VStack(spacing: 16) {
            Text("Show this code to your contact")
                .font(.headline)
            if let qrString = myPayload.qrString(), let image = QRCodeGenerator.image(for: qrString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
            } else {
                ProgressView()
            }
            Button("Scan Their Code Instead") {
                showScanner = true
            }
            .buttonStyle(.bordered)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var pairedConfirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Paired")
                .font(.headline)
            Text("Media you send in this conversation is now end-to-end encrypted.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func handleScan(_ string: String) {
        guard let payload = PairingPayload.decode(qrString: string) else {
            errorMessage = "That doesn't look like a walkytalky pairing code."
            return
        }
        guard payload.conversationId == conversationId else {
            errorMessage = "That code is for a different conversation."
            return
        }
        do {
            let key = try PairingService.deriveKey(peerPublicKeyData: payload.publicKey, conversationId: conversationId)
            ConversationKeyStore.store(conversationId: conversationId, keyVersion: nextVersion, key: key)
            errorMessage = nil
            didPair = true
        } catch {
            errorMessage = "Couldn't pair: \(error.localizedDescription)"
        }
    }
}

#Preview {
    PairingView(conversation: Conversation(participants: ["a", "b"]))
}
