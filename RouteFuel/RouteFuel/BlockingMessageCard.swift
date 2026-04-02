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
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("blocking-message-card")
    }
}
