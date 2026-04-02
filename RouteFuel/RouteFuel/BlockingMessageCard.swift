import SwiftUI

struct BlockingMessageCard: View {
    let message: BlockingMessage
    let retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message.title)
                .font(.headline)
            Text(message.body)
                .foregroundStyle(.secondary)

            if message.retryAction != nil, let retry {
                Button("Retry", action: retry)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("blocking-retry-button")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color(.systemBackground).opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        )
        .accessibilityIdentifier("blocking-message-card")
    }
}
