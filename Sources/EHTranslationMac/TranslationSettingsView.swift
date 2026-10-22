#if os(macOS)
import AppKit
import SwiftUI

struct TranslationSettingsView: View {
    @Bindable var workspace: TranslationWorkspace
    @State private var profileIndex = 0
    @State private var rawDraft = ""
    @State private var rawError: String?
    @State private var editingServices = false
    private let stages = [("textdetector", "文字检测", "detect"), ("ocr", "OCR 识别", "ocr"),
                          ("translator", "翻译", "translate"), ("inpainter", "图像修复", "inpaint")]
    private let languages = ["Auto", "日本語", "English", "简体中文", "繁體中文", "한국어", "Français", "Deutsch", "Español", "русский язык"]

    var body: some View {
        Form {
            if workspace.configuration["module"].object.isEmpty {
                Section { Text("请先在环境与模型中选择安装目录，或导入已有配置。").foregroundStyle(.secondary) }
            } else {
                Section("语言与流程") {
                    TranslationParameterEditor(value: field(["module", "translate_source"]), title: "源语言", options: languageOptions("sourceLanguages"))
                    TranslationParameterEditor(value: field(["module", "translate_target"]), title: "目标语言", options: languageOptions("targetLanguages"))
                    ForEach(stages, id: \.0) { stage, title, flag in
                        HStack {
                            Toggle(title, isOn: Binding(get: { workspace.configuration["module"].object["enable_" + flag]?.bool ?? true },
                                                   set: { workspace.configuration[path: ["module", "enable_" + flag]] = .bool($0) }))
                                .toggleStyle(.checkbox)
                            Spacer()
                            TranslationParameterEditor(value: field(["module", stage]), title: "\(title)模型", options: modelOptions(stage), showsLabel: false)
                        }
                        llmSelector(stage)
                    }
                }
                ForEach(stages, id: \.0) { stage, title, _ in
                    Section {
                        DisclosureGroup("\(title)参数") {
                            let model = workspace.configuration["module"][stage].string
                            let defaults = workspace.catalog[stage][model]["params"].object
                            let saved = workspace.configuration["module"][stage + "_params"][model].object
                            ForEach(Array(Set(defaults.keys).union(saved.keys)).sorted(), id: \.self) { key in
                                if !key.hasPrefix("__"), key != "description" {
                                    TranslationParameterEditor(value: parameter(stage: stage, model: model, key: key, fallback: defaults[key] ?? .null), title: key)
                                }
                            }
                        }
                    }
                }
                llmSection
                Section {
                    DisclosureGroup("上下文、嵌字与输出") {
                        ForEach(["translate_context", "llm_translate_context", "llm_prior_context_token_budget", "llm_glossary_path", "llm_glossary_mode", "llm_translate_vision", "llm_translate_summary_memory", "ocr_llm_page_level", "ocr_font_detect", "ocr_text_postprocess"], id: \.self) { key in
                            if workspace.configuration["module"].object[key] != nil {
                                TranslationParameterEditor(value: field(["module", key]), title: key)
                            }
                        }
                        ForEach(["font_family", "font_size", "vertical", "line_spacing", "stroke_width"], id: \.self) { key in
                            if workspace.configuration["global_fontformat"].object[key] != nil {
                                TranslationParameterEditor(value: field(["global_fontformat", key]), title: key,
                                                           options: key == "font_family" ? NSFontManager.shared.availableFontFamilies.sorted() : [],
                                                           allowsCustomValue: key == "font_family")
                            }
                        }
                        ForEach(["let_family_flag", "let_fntsize_flag", "let_writing_mode_flag", "imgsave_ext", "imgsave_quality"], id: \.self) { key in
                            if workspace.configuration.object[key] != nil { TranslationParameterEditor(value: field([key]), title: key) }
                        }
                    }
                }
                Section {
                    DisclosureGroup("完整配置（高级）") {
                        Text("用于编辑扩展字段。内容可能包含服务密钥，请勿分享。").font(.caption).foregroundStyle(.secondary)
                        SecureField("配置 JSON", text: $rawDraft)
                        HStack {
                            Button("载入当前配置") {
                                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                                rawDraft = (try? String(data: encoder.encode(workspace.configuration), encoding: .utf8)) ?? ""
                            }
                            Button("应用 JSON") {
                                do { workspace.configuration = try JSONDecoder().decode(TranslationJSON.self, from: Data(rawDraft.utf8)); rawError = nil; rawDraft = "" }
                                catch { rawError = "JSON 格式无效" }
                            }.disabled(rawDraft.isEmpty)
                        }
                        if let rawError { Text(rawError).foregroundStyle(.red) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disclosureGroupStyle(TranslationDisclosureStyle())
        .controlSize(.regular)
        .toolbar {
            ToolbarItem { Button("导入配置", systemImage: "square.and.arrow.down") { importPreset() } }
            ToolbarItem {
                Button("保存设置", systemImage: "checkmark") { workspace.saveSettings() }
                    .disabled(workspace.configuration["module"].object.isEmpty)
                    .accessibilityIdentifier("translation-save-settings")
            }
        }
    }

    private func languageOptions(_ key: String) -> [String] {
        let values = workspace.catalog["translator"][workspace.configuration["module"]["translator"].string][key].array.map(\.string)
        return values.isEmpty ? languages : values
    }

    private func modelOptions(_ stage: String) -> [String] {
        let current = workspace.configuration["module"][stage].string
        return Array(Set(workspace.catalog[stage].object.keys)
            .union(workspace.configuration["module"][stage + "_params"].object.keys)
            .union(current.isEmpty ? [] : [current])).sorted()
    }

    @ViewBuilder private func llmSelector(_ stage: String) -> some View {
        let required = stage == "translator" ? ("LLMTranslator", "translator_llm_id", "support_text") : stage == "ocr" ? ("LLMOCR", "ocr_llm_id", "support_vision") : ("LLMInpaint", "inpaint_llm_id", "support_image")
        let flag = stage == "translator" ? "translate" : stage == "inpainter" ? "inpaint" : "ocr"
        if workspace.configuration["module"][stage].string == required.0 && workspace.configuration["module"]["enable_" + flag] != .bool(false) {
            LabeledContent("LLM 服务配置") {
                Picker("LLM 服务配置", selection: field(["module", required.1])) {
                    Text("未选择").tag(TranslationJSON.string(""))
                    ForEach(workspace.configuration["module"]["llm_profiles"].array.filter { $0[required.2].bool }, id: \.self) { profile in
                        Text(profile["name"].string).tag(profile["id"])
                    }
                }
                .labelsHidden().pickerStyle(.menu).frame(width: 260)
            }
        }
    }

    private var llmSection: some View {
        Section {
            DisclosureGroup("LLM 服务与模型", isExpanded: $editingServices) {
                LabeledContent("服务配置") {
                    Picker("服务配置", selection: $profileIndex) {
                        ForEach(Array(workspace.configuration["module"]["llm_profiles"].array.enumerated()), id: \.offset) { index, profile in
                            Text(profile["name"].string).tag(index)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(width: 260)
                }
                Button("新增服务配置", systemImage: "plus") {
                    var profiles = workspace.configuration["module"]["llm_profiles"].array
                    profiles.append(.object(["id": .string(UUID().uuidString.lowercased()), "name": .string("新服务"),
                                             "backend": .string("openai"), "base_url": .string(""), "api_key": .string(""),
                                             "model": .string(""), "vision_model": .string(""), "image_model": .string(""),
                                             "image_base_url": .string(""), "prompt": .string(""), "vision_prompt": .string(""), "image_prompt": .string(""),
                                             "max_tokens": .number(4096), "temperature": .number(0.7), "top_p": .number(1), "require_api_key": .bool(true),
                                             "thinking_level": .string("Auto"), "vision_detail_level": .string("auto"),
                                             "support_text": .bool(true), "support_vision": .bool(false), "support_image": .bool(false)]))
                    workspace.configuration[path: ["module", "llm_profiles"]] = .array(profiles)
                    profileIndex = profiles.count - 1
                }
                if workspace.configuration["module"]["llm_profiles"].array.indices.contains(profileIndex) {
                    serviceFields.id(selectedProfile["id"])
                }
            }
        }
    }

    private var selectedProfile: TranslationJSON {
        let profiles = workspace.configuration["module"]["llm_profiles"].array
        return profiles.indices.contains(profileIndex) ? profiles[profileIndex] : .null
    }

    private var serviceFields: some View {
        Group {
            ForEach(["name", "backend", "base_url", "api_key", "support_text", "support_vision", "support_image"], id: \.self) { key in
                TranslationParameterEditor(value: profileField(key), title: key, options: key == "backend" ? ["openai", "codex"] : [])
            }
            if selectedProfile["support_text"].bool {
                profileEditor("model", allowsCustomValue: true)
                Button("刷新模型列表", systemImage: "arrow.clockwise") {
                    workspace.coordinator.perform("models", workspace: workspace, profileID: selectedProfile["id"].string)
                }
                .disabled(workspace.coordinator.isBusy || workspace.coordinator.isDraining || workspace.coordinator.enginePath.isEmpty)
                .accessibilityIdentifier("translation-refresh-service-models")
                Text("从当前服务读取可用模型，不下载模型或发起翻译。也可选择自定义模型名。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if selectedProfile["support_vision"].bool { profileEditor("vision_model", allowsCustomValue: true) }
            if selectedProfile["support_image"].bool { profileEditor("image_model", allowsCustomValue: true) }
            profileEditor("thinking_level")
            DisclosureGroup("请求参数与提示词") {
                ForEach(selectedProfile.object.keys.sorted().filter {
                    !$0.hasSuffix("_options") && !["id", "name", "backend", "base_url", "api_key", "model", "vision_model", "image_model", "thinking_level", "support_text", "support_vision", "support_image", "built_in", "title_url"].contains($0)
                }, id: \.self) { key in profileEditor(key) }
            }
        }
    }

    private func profileEditor(_ key: String, allowsCustomValue: Bool = false) -> some View {
        TranslationParameterEditor(value: profileField(key), title: key,
                                   options: selectedProfile[key + "_options"].array.map(\.string),
                                   allowsCustomValue: allowsCustomValue)
    }

    private func field(_ path: [String]) -> Binding<TranslationJSON> {
        Binding(get: { workspace.configuration[path: path] }, set: { workspace.configuration[path: path] = $0 })
    }
    private func parameter(stage: String, model: String, key: String, fallback: TranslationJSON) -> Binding<TranslationJSON> {
        let path = ["module", stage + "_params", model, key]
        return Binding(get: { TranslationSettingChoices.parameterValue(saved: workspace.configuration[path: path], fallback: fallback) },
                       set: { workspace.configuration[path: path] = $0 })
    }
    private func profileField(_ key: String) -> Binding<TranslationJSON> {
        Binding(get: {
            let profiles = workspace.configuration["module"]["llm_profiles"].array
            guard profiles.indices.contains(profileIndex) else { return .null }
            let value = profiles[profileIndex][key]
            return key == "thinking_level" && value == .null ? .string("Auto") : value
        }, set: { value in
            var profiles = workspace.configuration["module"]["llm_profiles"].array
            guard profiles.indices.contains(profileIndex) else { return }
            profiles[profileIndex][key] = value
            workspace.configuration[path: ["module", "llm_profiles"]] = .array(profiles)
        })
    }
    private func importPreset() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url { workspace.importPreset(url) }
        }
    }
}
#endif
