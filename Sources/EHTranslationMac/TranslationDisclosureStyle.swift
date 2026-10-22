#if os(macOS)
import SwiftUI

/// The entire header is a button, including the empty space after its title.
struct TranslationDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    configuration.label.font(.headline)
                    Spacer()
                    Text(configuration.isExpanded ? "收起" : "展开")
                        .font(.callout).foregroundStyle(.secondary)
                    Image(systemName: configuration.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.body.bold()).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "已展开" : "已折叠")
            if configuration.isExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    configuration.content
                }
                .padding(.vertical, 14)
            }
        }
    }
}
#endif
