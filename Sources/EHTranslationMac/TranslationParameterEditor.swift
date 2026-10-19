#if os(macOS)
import SwiftUI

/// Edits upstream descriptor values without discarding selector metadata.
struct TranslationParameterEditor: View {
    @Binding var value: TranslationJSON
    let title: String
    var options: [String] = []
    var allowsCustomValue = false
    @State private var editingCustomValue = false
    private var label: String { NSLocalizedString(TranslationParameterLabels.values[title] ?? title, comment: "Translation setting") }

    private var descriptor: Bool { value.isParameterDescriptor }
    private var current: TranslationJSON { descriptor ? value["value"] : value }
    private var choices: [TranslationJSON] { TranslationSettingChoices.choices(for: title, value: value, options: options) }
    private var secret: Bool {
        let key = title.lowercased()
        return key != "max_tokens" && ["api_key", "api key", "password", "secret", "token"].contains(where: key.contains)
    }

    var body: some View {
        if !secret && (!choices.isEmpty || allowsCustomValue) {
            VStack(alignment: .leading, spacing: 6) {
                Picker(label, selection: choiceBinding) {
                    ForEach(choices, id: \.self) { option in
                        Text(TranslationSettingChoices.label(for: option, key: title)).tag(Optional(option))
                    }
                    if allowsCustomValue { Text("自定义…").tag(Optional<TranslationJSON>.none) }
                }
                if allowsCustomValue && (editingCustomValue || choices.isEmpty) {
                    TextField("自定义\(label)", text: textBinding)
                        .accessibilityIdentifier("translation-custom-\(title)")
                }
            }
            .accessibilityIdentifier("translation-choice-\(title)")
        } else if case .bool = current {
            Toggle(label, isOn: Binding(get: { current.bool }, set: { set(.bool($0)) }))
        } else if case .number = current {
            TextField(label, value: Binding(get: { current.number }, set: { set(.number($0)) }), format: .number)
        } else if secret {
            HStack {
                SecureField(label, text: Binding(get: { current.string }, set: { if !current.object.isEmpty && $0.isEmpty { return }; set(.string($0)) }),
                            prompt: Text(current.object.isEmpty ? "输入密钥" : "已保存，输入以替换"))
                    .help(current.object.isEmpty ? "" : "已保存密钥；输入新值可替换，留空保留原值。")
                Button("清除密钥") { set(.string("")) }.controlSize(.small)
            }
        } else if case .string = current {
            TextField(label, text: Binding(get: { current.string }, set: { set(.string($0)) }), axis: .vertical)
                .lineLimit(1...6)
        } else if secret && !current.object.isEmpty {
            SecureField(title, text: Binding(get: { "" }, set: { if !$0.isEmpty { set(.string($0)) } }))
        } else {
            // Arrays and nested extension data remain intact and available in
            // the advanced JSON editor rather than being coerced to strings.
            LabeledContent(label, value: "高级配置")
        }
    }

    private var choiceBinding: Binding<TranslationJSON?> {
        Binding(get: { editingCustomValue || choices.isEmpty ? nil : current }, set: { option in
            editingCustomValue = option == nil
            if let option { set(option) }
        })
    }

    private var textBinding: Binding<String> {
        Binding(get: { current.string }, set: { set(.string($0)) })
    }

    private func set(_ updated: TranslationJSON) {
        if descriptor { value["value"] = updated } else { value = updated }
    }
}
#endif
