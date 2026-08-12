#ifndef EH_ARCHIVE_SUPPORT_H
#define EH_ARCHIVE_SUPPORT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct eh_archive_reader eh_archive_reader;

/// Opens a ZIP, 7z, RAR, or another format supported by the SDK's libarchive.
/// The returned reader owns all state until eh_archive_close is called.
eh_archive_reader *eh_archive_open(const char *path);

/// Advances to the next archive entry. The returned path is owned by the reader
/// and remains valid until the next call or close.
int eh_archive_next(
    eh_archive_reader *reader,
    const char **path,
    uint64_t *size,
    int *is_directory
);

/// Reads bytes from the current entry. Returns the number of bytes read, or a
/// negative value on failure.
int64_t eh_archive_read(eh_archive_reader *reader, void *buffer, size_t length);

/// Skips the remainder of the current entry.
int eh_archive_skip(eh_archive_reader *reader);

/// Returns a short error owned by the reader, or NULL when no detail exists.
const char *eh_archive_error(eh_archive_reader *reader);

/// Closes and releases the reader.
void eh_archive_close(eh_archive_reader *reader);

#ifdef __cplusplus
}
#endif

#endif
