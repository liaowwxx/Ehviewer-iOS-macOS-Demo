#if os(macOS)
import Foundation
import Testing
import EHDownloads
@testable import EHTranslationMac

struct TranslationSettingChoicesTests {
    @Test func descriptorSelectorsPreserveOrderTypesAndUnknownSelections() {
        let value: TranslationJSON = .object([
            "value": .number(3), "options": .array([.string("2"), .string("1"), .string("2")])
        ])
        #expect(TranslationSettingChoices.choices(for: "size", value: value) == [.number(2), .number(1), .number(3)])
        #expect(TranslationSettingChoices.choices(for: "model", value: .string("custom-model"), options: ["first", "second"]) ==
                [.string("first"), .string("second"), .string("custom-model")])
    }

    @Test func fixedOptionsKeepStorageValuesSeparateFromDisplayLabels() {
        let levels = TranslationSettingChoices.choices(for: "thinking_level", value: .string("Disabled"))
        #expect(levels.contains(.string("Disabled")))
        #expect(TranslationSettingChoices.label(for: .string("Disabled"), key: "thinking_level") == "关闭")
        #expect(TranslationSettingChoices.choices(for: "thinking_level", value: .string("custom"), options: ["low", "high"]) ==
                [.string("low"), .string("high"), .string("custom")])
        #expect(TranslationSettingChoices.defaults(for: "let_family_flag") == [.number(0), .number(1)])
        #expect(TranslationSettingChoices.defaults(for: "llm_translate_context") == [.string("page"), .string("history")])
    }

    @Test func savedScalarAndPartialDescriptorRecoverCatalogOptionsLosslessly() {
        let fallback: TranslationJSON = .object([
            "value": .string("cpu"), "options": .array([.string("cpu"), .string("mps")]), "type": .string("selector")
        ])
        let scalar = TranslationSettingChoices.parameterValue(saved: .string("mps"), fallback: fallback)
        #expect(scalar["value"] == .string("mps"))
        #expect(scalar["options"] == fallback["options"])
        let saved: TranslationJSON = .object(["value": .string("custom"), "future": .number(7)])
        let merged = TranslationSettingChoices.parameterValue(saved: saved, fallback: fallback)
        #expect(merged["future"] == .number(7))
        #expect(merged["options"] == fallback["options"])
        #expect(merged["value"] == .string("custom"))
    }

    @Test @MainActor func modelRefreshPreservesSelectedModelSecretsAndOtherProfilesAndRejectsStaleReplies() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = TranslationWorkspace(profileID: UUID(), files: TranslationFileStore(root: root), coordinator: TranslationCoordinator())
        let profile: TranslationJSON = .object([
            "id": .string("local"), "model": .string("custom-current"), "base_url": .string("http://localhost:11434/v1"),
            "api_key": .string("fixture-secret"), "future": .number(13), "vision_model_options": .array([.string("vision-model")])
        ])
        let other: TranslationJSON = .object(["id": .string("other"), "model": .string("other-model")])
        workspace.configuration = .object(["module": .object(["llm_profiles": .array([profile, other])])])
        try workspace.applyModelList(["installed-a", "installed-b"], to: profile)
        let updated = workspace.configuration["module"]["llm_profiles"].array
        #expect(updated[0]["model"] == profile["model"])
        #expect(updated[0]["api_key"] == profile["api_key"])
        #expect(updated[0]["future"] == profile["future"])
        #expect(updated[0]["vision_model_options"] == profile["vision_model_options"])
        #expect(updated[1] == other)
        #expect(updated[0]["model_options"] == .array([.string("installed-a"), .string("installed-b")]))
        #expect(throws: TranslationBridgeError.self) { try workspace.applyModelList(["stale"], to: profile) }
        #expect(throws: TranslationBridgeError.self) { try workspace.applyModelList([], to: updated[0]) }
        #expect(workspace.configuration["module"]["llm_profiles"].array == updated)
    }
}
#endif
