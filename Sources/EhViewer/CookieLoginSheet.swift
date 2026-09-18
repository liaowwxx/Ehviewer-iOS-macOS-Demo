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
import EHNetworking

struct CookieLoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var values = CookieLoginValues()
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cookie") {
                    cookieField(CookieHeader.memberIDName, value: $values.memberID, required: true)
                    cookieField(CookieHeader.passwordHashName, value: $values.passwordHash, required: true)
                    cookieField(CookieHeader.igneousName, value: $values.igneous, required: false)
                    Text("只需填写等号后的值；igneous 留空时，应用会在访问 ExHentai 时尝试自动获取。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cookie 登录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !isSaving, let header = values.cookieHeader else { return }
                        isSaving = true
                        Task {
                            let saved = await model.saveCookie(header)
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(isSaving || values.cookieHeader == nil)
                }
                ToolbarItem(placement: .status) {
                    if isSaving { ProgressView().accessibilityLabel(Text("正在保存")) }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func cookieField(_ name: String, value: Binding<String>, required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(verbatim: name + " =")
                    valueInput(name, value: value, required: required)
                }
                VStack(alignment: .leading) {
                    Text(verbatim: name + " =")
                    valueInput(name, value: value, required: required)
                }
            }
            if let error = values.error(for: name) {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func valueInput(_ name: String, value: Binding<String>, required: Bool) -> some View {
        TextField(required ? "必填" : "选填", text: value)
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityHint(Text(required ? "必填" : "选填"))
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()
            .disabled(isSaving)
            .onChange(of: value.wrappedValue) { _, input in
                // Strip only a matching name prefix; keep whitespace while typing.
                if let equal = input.firstIndex(of: "="),
                   input[..<equal].trimmingCharacters(in: .whitespaces) == name {
                    value.wrappedValue = String(input[input.index(after: equal)...])
                }
            }
    }
}
