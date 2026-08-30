# Archived files

- Archived at: 2026-08-17T00:30:55+08:00
  - Original path: `Sources/EHPersistence/MigrationSnapshot.swift`
  - Archived path: `deleted_file/2026-08-17T003055+0800/Sources/EHPersistence/MigrationSnapshot.swift`
  - Source/use: legacy broad JSON migration schema for galleries, local state, downloads, searches, filters, settings, and tag translations.
  - Reason: replaced by the metadata-only `.ehgallery` synchronization format at the user's request; retaining this implementation risks accidentally restoring the old full-state import path.
  - SHA-256 before archive: `98563ceb8fb0b2edda66fc5b396e7526093ad6311ee664c9424e3a1a8b2ece1c`
  - Restore: move the archived file back to its original relative path and restore the deprecated `PersistenceStore` APIs/tests if full-state migration is deliberately reintroduced.

- Archived at: 2026-08-29T17:07:25+08:00
  - Original path: `Sources/EhViewer/Resources/HELP.md`
  - Archived path: `deleted_file/2026-08-29T170725+0800/Sources/EhViewer/Resources/HELP.md`
  - Source/use: duplicate bundled usage guide left after consolidating app documentation resources under `Sources/EhViewer/Resources/Documentation/`.
  - Reason: consolidate the app's Markdown documentation into one editable resource directory at the user's request; the file content is retained in the new `Documentation/HELP.md` and this archive.
  - SHA-256 before archive: `b4ed855399c95b8350bb93be7e6bbc9904bb901c59461d82b495baa38d33a678`
  - Restore: move the archived file back to `Sources/EhViewer/Resources/HELP.md` and update the app resource reference if the legacy flat resource layout is deliberately restored.
