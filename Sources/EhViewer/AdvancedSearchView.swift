/*
 * EhViewer iOS/macOS — E-Hentai / ExHentai 画廊浏览客户端
 * Copyright (C) 2026 EhViewer Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

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
                        .accessibilityValue(draft.categories.contains(category) ? String(localized: "已选择") : String(localized: "未选择"))
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
