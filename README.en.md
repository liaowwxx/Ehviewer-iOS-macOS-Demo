# EhViewer iOS / macOS

[中文](README.md) | English

An **E-Hentai / ExHentai** gallery browser for iOS / iPadOS / macOS, natively built with SwiftUI and inspired by [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ).

> This app is intended solely for personal learning and accessing publicly available content. Please comply with local laws, regulations, and site terms.
>
> This project is developed with the assistance of Codex and is still a testing build; bugs or incomplete features may exist. If you encounter issues, please report them via Issues.

---

## Main Features

### Browsing & Search

- Home, subscriptions, popular, rankings, and favorites; supports advanced search with filters for category, rating, page count, and more.
- The search box provides tag suggestions and search history: tag candidates appear as you type, selecting one completes the tag syntax, and multiple tags can be combined.
- List cards display the cover, title, uploader, language tag, upload time, category, page count, and rating.
- Comprehensive tag-blocking support.

### Reading

- Vertical continuous reading and left-to-right / right-to-left paging; zoom, rotation, full-screen mode, and in-page navigation.
- Automatically records reading progress and supports saving media to the system photo library.
- On macOS, use the arrow keys or swipe on the trackpad to turn pages.

### Downloads

- Download queue, resumable downloads, and automatic retry on failure.
- Background downloads resume automatically after restart; the download page supports filtering by status, multiple sorting options, and tag management.
- Supports exporting download archives containing images or videos and restoring them through import.

### Easy Data Migration Between Devices

- Export metadata for downloaded galleries (`.ehgallery`) or archives (`.EHArchive`) from the current device, then quickly import them on another device via AirDrop.
- Android gallery archives can be imported into this app as compressed packages.

---

## Installation

### iOS: Recommended AltStore Sideloading

1. Install [AltStore](https://altstore.io) on a computer running Windows or macOS, sign in to AltServer, and refer to the [official AltStore documentation](https://faq.altstore.io/).
2. Download the latest `EhViewer.ipa` from the [Releases](../../releases) page.
3. Transfer the `.ipa` to your iPhone via AirDrop or Files, then open and install it with **AltStore**.
4. If you see "Untrusted Developer" on first launch, go to **Settings → General → VPN & Device Management** and trust your Apple ID.
5. The signature is valid for 7 days; keep your iPhone regularly connected to AltServer on your computer for **automatic renewal**.

## Login

- Browse public content without logging in (guest mode).
- Supports three login methods: **username & password**, **web login**, and **cookie login**. *(Untested)*
- After logging in, you can favorite, rate, comment on, and follow tags, as well as access ExHentai. *(Untested)*

---

## System Requirements

- iOS / iPadOS 26.0 or later; macOS 26.0 or later.

## Documentation

- [Online User Guide](https://liaowwxx.github.io/Ehviewer-iOS-macOS-Demo/)

## Privacy

- All data is stored locally; image caches and downloaded files remain inside the app sandbox.
- The app contains no analytics, tracking, or network reporting components.

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).

Reference implementation: [Ehviewer_CN_SXJ](https://github.com/xiaojieonly/Ehviewer_CN_SXJ).

Third-party component licenses are available in [NOTICE](NOTICE) and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).

The tag translation database comes from [EhTagTranslation](https://github.com/EhTagTranslation/Database) (CC-BY-NC-SA-3.0).
