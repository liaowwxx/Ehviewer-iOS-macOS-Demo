# Parser fixtures

These small fixtures preserve the markup needed by the parser tests from the Android reference project at commit `17769e4`:

- `app/src/test/resources/com/hippo/ehviewer/client/parser/GalleryPageParserTest.html`
- `app/src/test/resources/com/hippo/ehviewer/client/parser/GalleryPageApiParserTest.json`
- `app/src/test/resources/com/hippo/ehviewer/client/parser/GalleryDetail.html`

The files are intentionally trimmed to the stable parser contract rather than copying the complete site responses. They are test inputs only and do not contain credentials.

`advanced.html` is a credential-free synthetic fixture preserving the reference parser shapes for comments, Torrent, archiver and watched tags.
