# EhViewer iOS/macOS

Swift 6.3 / SwiftUI / SwiftData multi-platform baseline for iOS 26, iPadOS 26 and macOS 26.

## Build

```sh
swift test
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer -sdk macosx CODE_SIGNING_ALLOWED=NO build
```

The app starts with `使用演示数据` enabled for deterministic local browsing. Turn it off in Settings to use the built-in `EHClient` in guest mode; public lists, details and page images do not require a session, while remote favorites, comments, ratings and watched tags do. Local history and favorites remain available to guests. A valid session can be supplied through password login, the temporary WKWebView, or manual Cookie login. Passwords are never persisted; session cookies are isolated behind `SessionVault` and Keychain. Signing out returns to real guest browsing instead of silently switching back to demo data.

## Modules

- `EHDomain`: value types, routes and errors.
- `EHNetworking`: injectable URLSession boundary, E/EX URL rules, SwiftSoup HTML/parser-page API, Keychain session vault, OSLog and ImageIO-backed image cache.
- `EHPersistence`: SwiftData V1 schema and `@ModelActor` repository.
- `EHDownloads`: cancellable one-gallery download coordinator with three-page batches, bounded event streams, retry/error states, atomic Application Support files and background URLSession reconnect hooks.
- `Sources/EhViewer`: adaptive SwiftUI navigation, browse/detail/reader/download/library/settings vertical slice.
- `EHArchiveSupport`: local libarchive bridge for ZIP/7z/RAR and `Sources/EhViewerShare`: iOS Share Extension URL forwarding.

Downloads also exposes “打开本地归档” for document-based ZIP/7z/RAR reading. The reader keeps the selected document security-scoped and extracts only the chosen image entry. The Share Extension forwards a shared public URL into the app; it never receives or stores passwords or session cookies.

The Android behavior baseline is documented in [NOTICE](NOTICE) and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
