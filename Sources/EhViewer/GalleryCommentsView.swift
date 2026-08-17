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

struct GalleryCommentsView: View {
    @Environment(AppModel.self) private var model
    let key: GalleryKey
    @State private var comments: [GalleryComment] = []
    @State private var commentText = ""
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var loadToken = UUID()

    var body: some View {
        Group {
            if isLoading && comments.isEmpty {
                ProgressView("加载中…")
            } else if let errorMessage, comments.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView("加载失败", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                    Button("重试", systemImage: "arrow.clockwise") {
                        loadToken = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if comments.isEmpty {
                            ContentUnavailableView("评论", systemImage: "text.bubble")
                                .frame(maxWidth: .infinity)
                        } else {
                            ForEach(comments) { comment in
                                GalleryCommentCard(comment: comment)
                            }
                        }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("评论")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GalleryCommentComposer(
                text: $commentText,
                canSubmit: model.isGuestMode == false,
                isSubmitting: isSubmitting
            ) {
                submitComment()
            }
        }
        .task(id: "\(key.id)-\(loadToken)") {
            await loadComments()
        }
        .accessibilityIdentifier("gallery-comments-screen")
    }

    private func loadComments() async {
        isLoading = true
        errorMessage = nil
        do {
            let loadedComments = try await model.comments(for: key)
            guard Task.isCancelled == false else { return }
            comments = loadedComments
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func submitComment() {
        let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.isEmpty == false, model.isGuestMode == false, isSubmitting == false else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            if let updatedComments = await model.submitComment(for: key, body: body) {
                comments = updatedComments
                commentText = ""
            }
        }
    }
}

struct GalleryCommentCard: View {
    let comment: GalleryComment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.author).font(.subheadline.bold())
                Spacer()
                if let postedAt = comment.postedAt {
                    Text(postedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if comment.score != 0 {
                    Text("评分 \(comment.score)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(comment.body)
                .font(.callout)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct GalleryCommentComposer: View {
    @Binding var text: String
    let canSubmit: Bool
    let isSubmitting: Bool
    let submit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            TextField(canSubmit ? "写评论" : "登录后发表评论", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .disabled(canSubmit == false)
            Button(action: submit) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Label("发布评论", systemImage: "paperplane")
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("发布评论")
            .disabled(isSubmitting || canSubmit == false || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
