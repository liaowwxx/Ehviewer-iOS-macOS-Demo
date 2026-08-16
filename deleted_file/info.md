# Archived files

- Archived at: 2026-08-17T00:30:55+08:00
  - Original path: `Sources/EHPersistence/MigrationSnapshot.swift`
  - Archived path: `deleted_file/2026-08-17T003055+0800/Sources/EHPersistence/MigrationSnapshot.swift`
  - Source/use: legacy broad JSON migration schema for galleries, local state, downloads, searches, filters, settings, and tag translations.
  - Reason: replaced by the metadata-only `.ehgallery` synchronization format at the user's request; retaining this implementation risks accidentally restoring the old full-state import path.
  - SHA-256 before archive: `98563ceb8fb0b2edda66fc5b396e7526093ad6311ee664c9424e3a1a8b2ece1c`
  - Restore: move the archived file back to its original relative path and restore the deprecated `PersistenceStore` APIs/tests if full-state migration is deliberately reintroduced.
