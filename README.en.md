# EhViewer iOS / macOS

[中文](README.md) | English

An **E-Hentai / ExHentai** gallery browser for iOS / iPadOS / macOS, natively built with SwiftUI and inspired by [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ).

> This app is intended solely for personal learning and accessing publicly available content. Please comply with local laws, regulations, and site terms.
>
> This project is developed with the assistance of Codex and is still a testing build; bugs or incomplete features may exist. If you encounter issues, please report them via Issues.

---

## Features

### Browsing & Search

- Home, subscriptions, popular, top lists, and favorites; supports advanced search (filters by category, rating, page count, and more).
- The search box features **tag suggestions** and **search history**: tag candidates appear as you type, tap to auto-complete into tag syntax, and multiple tags can be combined.
- List cards display: cover, title, uploader, language tag, upload time, category, page count, and rating.

### Reading

- Vertical continuous reading and left-right / right-left paging; zoom, rotation, full screen, and in-page navigation.
- Automatically records reading progress and supports saving media to the system photo library.

### Downloads

- Single-task download queue, resumable downloads, and automatic retry on failure.
- Background downloads resume automatically after restart; the download page supports filtering by status, multiple sorting options, and tag management.
- Supports exporting download archives (including images/videos) and restoring imports.

### Easy Migration from Android

- **Supports directly importing download archives or JSON**

---

## Installation

### Recommended: AltStore Sideloading

1. Install [AltStore](https://altstore.io) on your computer (Windows/macOS) and sign in to AltServer.
2. Download the latest `EhViewer.ipa` from the [Releases](../../releases) page.
3. Transfer the `.ipa` to your iPhone via AirDrop or file transfer, then open and install it with **AltStore**.
4. If you see "Untrusted Developer" on first launch, go to **Settings → General → VPN & Device Management** and trust your Apple ID.
5. Free Apple ID signatures are valid for 7 days; keep your iPhone regularly connected to AltServer on your computer for **automatic renewal**.

### Build the IPA Yourself

```sh
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer \
  -sdk iphoneos -configuration Release \
  -archivePath build/EhViewer.xcarchive archive
zsh make-ipa.sh build/EhViewer.xcarchive EhViewer.ipa
```

## Login

- Browse public content without logging in (guest mode).
- Supports three login methods: **username & password**, **web login**, and **cookie login**.
- The password is used only for the current login request; session cookies are encrypted and stored in the system keychain.
- After logging in, you can favorite/rate/comment/watch tags and access ExHentai. (Untested)

---

## System Requirements

- iOS / iPadOS 26.0 or later; macOS 26.0 or later.

## Privacy

- All data is stored locally only; image caches and downloaded files reside within the app sandbox.
- Contains no statistics, tracking, or networked reporting components.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

Reference implementation: [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ); third-party component licenses are available in [NOTICE](NOTICE) and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md). The tag translation database comes from [EhTagTranslation](https://github.com/EhTagTranslation/Database) (CC-BY-NC-SA-3.0).
