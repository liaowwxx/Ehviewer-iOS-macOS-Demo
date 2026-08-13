import SwiftUI
import EHDomain

struct AdvancedSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: GalleryAdvancedSearch
    let apply: (GalleryAdvancedSearch) -> Void
    let clear: () -> Void

    init(
        initialValue: GalleryAdvancedSearch?,
        apply: @escaping (GalleryAdvancedSearch) -> Void,
        clear: @escaping () -> Void
    ) {
        _draft = State(initialValue: initialValue ?? GalleryAdvancedSearch())
        self.apply = apply
        self.clear = clear
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("分类") {
                    ForEach(GalleryCategory.allCases) { category in
                        Button {
                            draft.toggle(category)
                        } label: {
                            HStack {
                                Text(category.rawValue)
                                Spacer()
                                if draft.categories.contains(category) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("advanced-search-category-\(category.id)")
                        .accessibilityValue(draft.categories.contains(category) ? "已选择" : "未选择")
                    }
                    HStack {
                        Button("全选") {
                            draft.categories = Set(GalleryCategory.allCases)
                        }
                        Spacer()
                        Button("全部取消") {
                            draft.categories.removeAll()
                        }
                    }
                }

                Section("画廊条件") {
                    Toggle("仅显示有种子的画廊", isOn: $draft.onlyWithTorrents)
                    Toggle("浏览已删除的画廊", isOn: $draft.onlyShowExpunged)
                }

                Section("评分与页数") {
                    Picker("最低评分", selection: $draft.minimumRating) {
                        Text("不限").tag(0)
                        ForEach(2...5, id: \.self) { rating in
                            Text("\(rating) 星").tag(rating)
                        }
                    }
                    TextField("最少页数（0 表示不限）", value: $draft.minimumPageCount, format: .number)
                    TextField("最多页数（0 表示不限）", value: $draft.maximumPageCount, format: .number)
                    if draft.hasValidPageRange == false {
                        Label("最多页数不能小于最少页数", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section("禁用默认排除项") {
                    Toggle("语言", isOn: $draft.disableLanguageFilter)
                    Toggle("上传者", isOn: $draft.disableUploaderFilter)
                    Toggle("标签", isOn: $draft.disableTagFilter)
                }

                Section {
                    Button("停用高级搜索", systemImage: "xmark.circle", role: .destructive) {
                        clear()
                        dismiss()
                    }
                }
            }
            .navigationTitle("高级搜索")
            .accessibilityIdentifier("advanced-search-form")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        apply(draft)
                        dismiss()
                    }
                    .disabled(draft.categories.isEmpty || draft.hasValidPageRange == false)
                    .accessibilityIdentifier("apply-advanced-search")
                }
            }
        }
    }
}
