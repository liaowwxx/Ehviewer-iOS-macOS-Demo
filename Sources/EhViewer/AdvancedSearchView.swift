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
#if os(macOS)
        macOSBody
#else
        mobileBody
#endif
    }

#if os(macOS)
    private var macOSBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    macOSCategoriesSection
                    macOSGalleryConditionsSection
                    macOSRatingSection
                    macOSDefaultFiltersSection

                    Button("停用高级搜索", systemImage: "xmark.circle", role: .destructive) {
                        clear()
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .padding(.top, 2)
                }
                .padding(24)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .navigationTitle("高级搜索")
            .accessibilityIdentifier("advanced-search-form")
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
        .frame(minWidth: 600, idealWidth: 680, minHeight: 620, idealHeight: 720)
    }

    private var macOSCategoriesSection: some View {
        GroupBox("分类") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(GalleryCategory.allCases) { category in
                        let isSelected = draft.categories.contains(category)
                        Button {
                            draft.toggle(category)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                Text(category.rawValue)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .padding(.horizontal, 8)
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                        .accessibilityIdentifier("advanced-search-category-\(category.id)")
                        .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
                    }
                }

                HStack(spacing: 12) {
                    Button("全选") {
                        draft.categories = Set(GalleryCategory.allCases)
                    }
                    Button("全部取消") {
                        draft.categories.removeAll()
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var macOSGalleryConditionsSection: some View {
        GroupBox("画廊条件") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("仅显示有种子的画廊", isOn: $draft.onlyWithTorrents)
                Toggle("浏览已删除的画廊", isOn: $draft.onlyShowExpunged)
            }
            .toggleStyle(.checkbox)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var macOSRatingSection: some View {
        GroupBox("评分与页数") {
            VStack(alignment: .leading, spacing: 10) {
                macOSLabeledRow("最低评分") {
                    Picker("最低评分", selection: $draft.minimumRating) {
                        Text("不限").tag(0)
                        ForEach(2...5, id: \.self) { rating in
                            Text("\(rating) 星").tag(rating)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)
                }
                macOSLabeledRow("最少页数") {
                    TextField("0 表示不限", value: $draft.minimumPageCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                macOSLabeledRow("最多页数") {
                    TextField("0 表示不限", value: $draft.maximumPageCount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                if draft.hasValidPageRange == false {
                    Label("最多页数不能小于最少页数", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .padding(.leading, 136)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var macOSDefaultFiltersSection: some View {
        GroupBox("禁用默认排除项") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("语言", isOn: $draft.disableLanguageFilter)
                Toggle("上传者", isOn: $draft.disableUploaderFilter)
                Toggle("标签", isOn: $draft.disableTagFilter)
            }
            .toggleStyle(.checkbox)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func macOSLabeledRow<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .frame(width: 120, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
#else
    private var mobileBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    mobileCategoriesSection
                    mobileGalleryConditionsSection
                    mobileRatingSection
                    mobileDefaultFiltersSection

                    Button("停用高级搜索", systemImage: "xmark.circle", role: .destructive) {
                        clear()
                        dismiss()
                    }
                    .padding(.top, 2)
                }
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .navigationTitle("高级搜索")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("advanced-search-form")
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

    private var mobileCategoriesSection: some View {
        GroupBox("分类") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(GalleryCategory.allCases) { category in
                        let isSelected = draft.categories.contains(category)
                        Button {
                            draft.toggle(category)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                                Text(category.rawValue)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .padding(.horizontal, 10)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .accessibilityIdentifier("advanced-search-category-\(category.id)")
                        .accessibilityValue(isSelected ? String(localized: "已选择") : String(localized: "未选择"))
                    }
                }

                HStack(spacing: 12) {
                    Button("全选") {
                        draft.categories = Set(GalleryCategory.allCases)
                    }
                    Button("全部取消") {
                        draft.categories.removeAll()
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
        }
    }

    private var mobileGalleryConditionsSection: some View {
        GroupBox("画廊条件") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("仅显示有种子的画廊", isOn: $draft.onlyWithTorrents)
                Toggle("浏览已删除的画廊", isOn: $draft.onlyShowExpunged)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var mobileRatingSection: some View {
        GroupBox("评分与页数") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("最低评分")
                    Spacer()
                    Picker("最低评分", selection: $draft.minimumRating) {
                        Text("不限").tag(0)
                        ForEach(2...5, id: \.self) { rating in
                            Text("\(rating) 星").tag(rating)
                        }
                    }
                    .pickerStyle(.menu)
                }
                TextField("最少页数（0 表示不限）", value: $draft.minimumPageCount, format: .number)
                    .textFieldStyle(.roundedBorder)
                TextField("最多页数（0 表示不限）", value: $draft.maximumPageCount, format: .number)
                    .textFieldStyle(.roundedBorder)
                if draft.hasValidPageRange == false {
                    Label("最多页数不能小于最少页数", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            .padding(10)
        }
    }

    private var mobileDefaultFiltersSection: some View {
        GroupBox("禁用默认排除项") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("语言", isOn: $draft.disableLanguageFilter)
                Toggle("上传者", isOn: $draft.disableUploaderFilter)
                Toggle("标签", isOn: $draft.disableTagFilter)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
}
