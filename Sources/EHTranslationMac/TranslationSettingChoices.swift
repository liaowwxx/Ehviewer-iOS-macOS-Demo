#if os(macOS)
import Foundation

/// Selector values retain their JSON types and upstream order when saved.
enum TranslationSettingChoices {
    static func defaults(for key: String) -> [TranslationJSON] {
        let strings: [String]
        switch key {
        case "thinking_level": strings = ["Auto", "Disabled", "minimal", "low", "medium", "high", "xhigh"]
        case "vision_detail_level": strings = ["None", "auto", "low", "high"]
        case "translate_context": strings = ["textblock", "page"]
        case "llm_translate_context": strings = ["page", "history"]
        case "llm_glossary_mode": strings = ["matching", "all"]
        case "ocr_text_postprocess": strings = ["none", "capitalize", "uppercase"]
        case "imgsave_ext": strings = [".png", ".jpg", ".webp"]
        case "let_family_flag", "let_fntsize_flag", "let_writing_mode_flag": return [.number(0), .number(1)]
        default: return []
        }
        return strings.map(TranslationJSON.string)
    }

    static func choices(for key: String, value: TranslationJSON, options: [String] = []) -> [TranslationJSON] {
        let current = value.isParameterDescriptor ? value["value"] : value
        let supplied = options.isEmpty ? value["options"].array : options.map(TranslationJSON.string)
        let source = supplied.isEmpty ? defaults(for: key) : supplied
        guard !source.isEmpty else { return [] }
        var choices: [TranslationJSON] = []
        for option in source + [current] {
            var item = option
            if case .number = current, case .string(let text) = item, let number = Double(text) { item = .number(number) }
            guard item != .null, !choices.contains(item) else { continue }
            if case .string(let text) = item, text.isEmpty { continue }
            choices.append(item)
        }
        // Empty is a valid selection, for example a model not yet configured.
        if current == .string("") { choices.insert(current, at: 0) }
        return choices
    }

    static func label(for value: TranslationJSON, key: String) -> String {
        if value == .string("") { return "未选择" }
        if ["let_family_flag", "let_fntsize_flag", "let_writing_mode_flag"].contains(key) {
            if value == .number(1) { return "使用全局设置" }
            if value == .number(0) { return key == "let_family_flag" ? "保留原有字体" : "自动识别" }
        }
        let labels: [String: [String: String]] = [
            "thinking_level": ["Auto": "自动（服务默认）", "Disabled": "关闭", "minimal": "最低", "low": "低", "medium": "中", "high": "高", "xhigh": "最高"],
            "vision_detail_level": ["None": "服务默认", "auto": "自动", "low": "低", "high": "高"],
            "translate_context": ["textblock": "逐文本块", "page": "整页"],
            "llm_translate_context": ["page": "仅当前页", "history": "包含历史页面"],
            "llm_glossary_mode": ["matching": "仅匹配的术语", "all": "全部术语"],
            "ocr_text_postprocess": ["none": "不处理", "capitalize": "首字母大写", "uppercase": "全部大写"],
            "imgsave_ext": [".png": "PNG", ".jpg": "JPEG", ".webp": "WebP"]
        ]
        return labels[key]?[value.string] ?? value.string
    }

    static func parameterValue(saved: TranslationJSON, fallback: TranslationJSON) -> TranslationJSON {
        guard saved != .null else { return fallback }
        guard fallback.isParameterDescriptor else { return saved }
        if saved.isParameterDescriptor {
            return .object(fallback.object.merging(saved.object) { _, saved in saved })
        }
        var descriptor = fallback
        descriptor["value"] = saved
        return descriptor
    }
}
#endif
