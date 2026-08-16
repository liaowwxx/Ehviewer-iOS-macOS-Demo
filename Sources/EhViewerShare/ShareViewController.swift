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

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private var didHandle = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard didHandle == false else { return }
        didHandle = true
        Task { @MainActor in await forwardSharedURL() }
    }

    @MainActor
    private func forwardSharedURL() async {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = extensionItem.attachments?.first else {
            showFailure("没有找到可分享的链接。")
            return
        }

        var sharedURL = await loadURL(from: provider)
        if sharedURL == nil {
            sharedURL = await loadTextURL(from: provider)
        }
        guard let sharedURL,
              var components = URLComponents(string: "ehviewer://open") else {
            showFailure("无法识别分享内容，请分享画廊网页或 URL。")
            return
        }
        components.queryItems = [URLQueryItem(name: "url", value: sharedURL.absoluteString)]
        guard let callbackURL = components.url else {
            showFailure("无法生成应用打开链接。")
            return
        }
        guard await extensionContext?.open(callbackURL) == true else {
            showFailure("EhViewer 未能打开该链接，请确认主应用可用。")
            return
        }
        complete()
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func loadTextURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let text: String?
                if let value = item as? String {
                    text = value
                } else if let data = item as? Data {
                    text = String(data: data, encoding: .utf8)
                } else {
                    text = nil
                }
                continuation.resume(returning: text.flatMap(URL.init(string:)))
            }
        }
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    @MainActor
    private func showFailure(_ message: String) {
        let alert = UIAlertController(title: "无法分享", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.extensionContext?.cancelRequest(withError: NSError(
                domain: "EhViewerShare",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
        })
        present(alert, animated: true)
    }
}
