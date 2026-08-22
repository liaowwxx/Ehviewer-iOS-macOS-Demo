# Repository Guidelines

## Project Structure & Module Organization

- `Sources/EHDomain` contains shared value types, routes, and errors.
- `Sources/EHNetworking`, `Sources/EHPersistence`, and `Sources/EHDownloads` provide networking/parsing, SwiftData persistence, and download/archive workflows.
- `Sources/EhViewer` is the SwiftUI application; `Sources/EhViewerShare` is the iOS Share Extension; `Sources/EHArchiveSupport` contains the libarchive C bridge.
- `Tests/EhViewerTests` holds Swift Testing unit/integration tests and HTML/JSON fixtures. `Tests/EhViewerUITests` contains XCTest UI coverage.
- `EhViewer.xcodeproj` and `Package.swift` define the Xcode app and Swift Package targets. Keep icons and other artwork in the existing `icon.icon/` and `icon Exports/` directories.

## Build, Test, and Development Commands

```sh
swift test
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer -sdk macosx CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EhViewer.xcodeproj -scheme EhViewer test
zsh make-ipa.sh path/to/App.xcarchive output.ipa
```

`swift test` runs package tests; the two `xcodebuild` commands validate iOS Simulator and macOS builds. Run the Xcode test command for UI tests, and use the shared `EhViewer-TSAN` scheme when investigating concurrency issues. The IPA script packages an existing archive and validates its contents.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift formatting. Name types and protocols with `UpperCamelCase`; name methods, properties, and test functions with `lowerCamelCase`. Prefer small, focused types, explicit access control on public APIs, value semantics, and Swift concurrency annotations (`async`, `Sendable`, actors) consistent with neighboring code. No repository formatter or linter configuration is present, so preserve the surrounding style and let Xcode format code where appropriate.

## Testing Guidelines

Place unit tests beside the module they exercise conceptually, use descriptive behavior-oriented `@Test` names, and add reusable inputs under `Tests/EhViewerTests/Fixtures`. UI tests use `test...` XCTest methods and should launch in guest mode when authentication is not under test. No coverage threshold is documented; every behavior change should include focused tests and relevant UI coverage.

## Commit & Pull Request Guidelines

Recent commits use concise, action-oriented descriptions, commonly in Chinese, with occasional prefixes such as `feat:`. Keep commits focused and avoid unrelated formatting churn. Pull requests should explain the user-visible or architectural change, list validation commands, link an issue when applicable, and include simulator screenshots or recordings for UI changes. Never include passwords, session cookies, or local build artifacts.


xcrun agvtool new-marketing-version 1.2.0
xcrun agvtool new-version -all 2